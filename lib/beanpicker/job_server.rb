require File.expand_path( File.join(File.dirname(__FILE__), "..", "beanpicker") )

BEANPICKER_CLIENT_JOB = { :child => false }

module Beanpicker

  class Server

    include MsgLogger

    def initialize(args=ARGV)
      @args = args
    end

    def run
      debug "Hiring workers..."
      for arg in @args
        Worker.new arg
      end

      w = c = 0
      for worker in Beanpicker::workers
        w += 1
        m = "Worker: #{worker.name} hired to do"
        f = {}
        for child in worker.childs
          c += 1
          f[child.job_name] ||= 0
          f[child.job_name] += 1
        end
        for job in f.keys.sort
          m << " #{job}##{f[job]}"
        end
        debug m
      end

      if w == 0
        fatal ["NOBODY WANT TO WORK TO YOU!!",
               "Have you specified a file?",
               "e.g. #{$0} lib/my_file_with_jobs.rb"].join("\n")
        exit
      end

      if c == 0
        fatal ["ALL YOUR #{w} WORKER#{"S" if w > 1} ARE LAZY AND DON'T WANT TO DO ANYTHING!!",
               "Have you specified a job in any of yous files?",
               "e.g. job('no.lazy.worker') { |args| puts args[:my_money] }"].join("\n")
        exit
      end

      debug "#{w} worker#{"s" if w > 1} hired to do #{c} job#{"s" if c > 1}, counting the money..."
      
      sleep 1 while true
    end

  end

  class Worker

    include MsgLogger

    attr_accessor :childs
    attr_reader :name

    def initialize(filepath=nil, args={}, &blk)
      @childs = []
      @name   = args[:name] rescue nil
      if filepath
        @name = filepath.split(/[\\\/]/)[-1].gsub(/\.[^\.]+$/,'').split(/[_\.]/).map do |x|
          x.capitalize
        end.join if @name.nil?

        begin
          instance_eval File.read(filepath)
        rescue => e
          error Beanpicker::exception_message(e, "when loading file #{filepath}")
        end
      end

      if block_given?
        begin
          instance_eval(&blk)
        rescue => e
          error Beanpicker::exception_message(e, "when evaluating block")
        end
      end

      @name = "BeanpickerWorker without name" unless @name
      Beanpicker::add_worker(self)
    end

    def work_loop
      loop { sleep 1 }
    end

    def job(name, args={}, &blk)
      opts = { 
        :childs   => Beanpicker::default_childs_number,
        :log_file => nil,
        :fork     => Beanpicker::default_fork
      }.merge(args)

      @childs += Child.process(name, opts, &blk)
    end

    class Child

      include MsgLogger

      def self.process(job, opts, &blk)
        (opts[:childs]).times.map do |i|
          Child.new(job, opts, i, &blk)
        end
      end


      attr_reader :job_name, :number
      def initialize(job, opts, number, &blk)
        @job_name  = job
        @opts      = { :fork => false }.merge(opts)
        @number    = number
        @blk       = blk
        @loop      = nil
        @pid       = nil
        @beanstalk = Beanpicker::new_beanstalk
        @run       = true
        @job       = nil
        @fork      = @opts[:fork]
        start_watch
        start_loop
      end

      def beanstalk
        @beanstalk
      end

      def start_watch
        beanstalk.watch(@job_name)
        beanstalk.list_tubes_watched.each do |server, tubes|
          tubes.each { |tube| beanstalk.ignore(tube) unless tube == @job_name }
        end
      end

      def start_loop
        return false if @loop and @loop.alive?
        @loop = Thread.new(self) do |child|
          work_loop(child)
        end
      end

      def work_loop(child)
        start_work(child) while @run
      end

      def start_work(child)
        fork do
          BEANPICKER_CLIENT_JOB[:child] = true if @fork
          $0 = "[Beanpicker Child] #{@job_name}##{@number}" if @fork

          begin
            @job = child.beanstalk.reserve
            BEANPICKER_CLIENT_JOB[:job] = @job if @fork
            data  = @job.ybody

            if not data.is_a?(Hash) or [:args, :next_jobs] - data.keys != []
              data = { :args => data, :next_jobs => [] }
            end

            t=Time.now
            debug "Running #{@job_name}##{@number} with args #{data[:args]}; next jobs #{data[:next_jobs]}"
            r = @blk.call(data[:args].clone)
            debug "Job #{@job_name}##{@number} finished in #{Time.now-t} seconds with return #{r}"
            data[:args].merge!(r) if r.is_a?(Hash)

            @job.delete

            Beanpicker.enqueue(data[:next_jobs], data[:args]) if r and not data[:next_jobs].empty?
          rescue => e
            fatal Beanpicker::exception_message(e, "in loop of #{@job_name}##{@number} with pid #{Process.pid}")
            @job.bury rescue nil
          ensure
            @job = nil
          end
        end
      end

      def fork(&blk)
        if @fork
          ppid = Process.pid
          @pid = Kernel.fork do

            #hack for forked child die when parent receive a KILL(headshot?)
            Thread.new do
              begin
                while true
                  Process.kill 0, ppid
                  sleep 1
                end
              rescue Errno::ESRCH
                Kernel.exit
              end
            end

            blk.call

          end
          Process.waitpid @pid
          @pid = nil
        else
          blk.call
        end
      end

      def die!
        @run = false
        @loop.kill if @loop and @loop.alive?
        if @fork
          if @pid
            debug "Killing child with pid #{@pid}"
            Process.kill "TERM", @pid
            Thread.new do
              sleep 1
              Process.kill "KILL", @pid
            end
            begin
              Process.kill 0, @pid
              Process.waitpid @pid
            rescue Errno::ESRCH, Errno::ECHILD
              return
            end
          end
        else
          @job.bury rescue nil if @job
        end
      end

    end

  end

end

# kill childs or stop jobs
at_exit do
  if BEANPICKER_CLIENT_JOB[:child]
    Thread.new do
      sleep 1
      Kernel.exit
    end
    BEANPICKER_CLIENT_JOB[:job].bury rescue nil if BEANPICKER_CLIENT_JOB[:job]
  else
    Beanpicker::debug "Laying off workers..." if Beanpicker::workers.count > 0
    Beanpicker::stop_workers
  end
end

# hide errors throwed with ctrl+c
trap("INT") {
  puts unless BEANPICKER_CLIENT_JOB[:child]
  exit
}
