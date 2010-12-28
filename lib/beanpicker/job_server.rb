require File.expand_path( File.join(File.dirname(__FILE__), "..", "beanpicker") )
require File.expand_path( File.join(File.dirname(__FILE__), "process") )

BEANPICKER_FORK = { :child_every => false, :child_master => false, :child_pid => 0 }

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

    def log_handler
      Beanpicker::log_handler
    end

    def log_handler=(v)
      Beanpicker::log_handler=(v)
    end

  end

  class Worker

    include MsgLogger

    attr_reader :name, :reader, :childs

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

    def job(name, args={}, &blk)
      @childs << Child.process(name, args, self, &blk)
      @childs.flatten!
    end

    def log_handler
      @log_handler || Beanpicker::log_handler
    end

    def log_file(f)
      #without self call don't call log_handler= of this class Oo
      self.log_handler = f
    end

    class Child

      include MsgLogger

      def self.process(job, opts={}, worker=nil, &blk)
        (opts[:childs] || Beanpicker::default_childs_number).times.map do |i|
          Child.new(job, opts, i, worker, &blk)
        end
      end


      attr_reader :job_name, :number, :fork_every, :fork_master, :fork_every_pid, :fork_master_pid, :opts, :worker
      def initialize(job, opts={}, number=0, worker=nil, &blk)
        @job_name    = job
        @opts        = {
          :childs      => Beanpicker::default_childs_number,
          :fork_every  => Beanpicker::default_fork_every,
          :fork_master => Beanpicker::default_fork_master
        }.merge(opts)
        @number      = number
        @blk         = blk
        @loop        = nil
        @beanstalk   = Beanpicker::new_beanstalk
        @run         = true
        @job         = nil
        @worker      = worker
        if @opts[:fork]
          _fork_every  = @opts[:fork].to_s == 'every'
          _fork_master = @opts[:fork].to_s == 'master'
        else
          _fork_every  = !!@opts[:fork_every]
          _fork_master = !!@opts[:fork_master]
        end
        #really need self
        self.log_handler = @opts[:log_file] unless @opts[:log_file].nil?
        @fork_every  = Beanpicker::fork_every.nil?  ? _fork_every  : Beanpicker::fork_every
        @fork_master = Beanpicker::fork_master.nil? ? _fork_master : Beanpicker::fork_master
        @fork_master_pid = nil
        @fork_every_pid  = nil
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
        if @fork_master
          fork_master_child_and_monitor
        else
          @loop = Thread.new(self) do |child|
            work_loop(child)
          end
        end
      end

      def work_loop(child)
        start_work(child) while @run
      end

      def start_work(child=self)
        fork do
          begin
            @job = child.beanstalk.reserve
            BEANPICKER_FORK[:job] = @job if BEANPICKER_FORK[:child_every]
            data  = @job.ybody

            if not data.is_a?(Hash) or [:args, :next_jobs] - data.keys != []
              data = { :args => data, :next_jobs => [] }
            end

            t=Time.now
            debug "Running #{@job_name}##{@number} with args #{data[:args]}; next jobs #{data[:next_jobs]}"
            r = @blk.call(data[:args].clone)
            debug "Job #{@job_name}##{@number} finished in #{Time.now-t} seconds with return #{r}"
            data[:args].merge!(r) if r.is_a?(Hash) and data[:args].is_a?(Hash)

            @job.delete

            Beanpicker.enqueue(data[:next_jobs], data[:args]) if r and not data[:next_jobs].empty?
          rescue => e
            fatal Beanpicker::exception_message(e, "in loop of #{@job_name}##{@number} with pid #{Process.pid}")
            if BEANPICKER_FORK[:child_every]
              exit
            else
              Thread.new(@job) { |j| j.bury rescue nil }
            end
          ensure
            @job = nil
          end
        end
      end

      def fork(&blk)
        if @fork_every
          @fork_every_pid = pid = Kernel.fork do
            BEANPICKER_FORK[:child_every] = true
            Process.die_with_parent
            at_exit_to_every_child_fork
            $0 = "Beanpicker job child #{@job_name}##{@number} of #{Process.ppid}"
            blk.call
          end
          if BEANPICKER_FORK[:child_master]
            BEANPICKER_FORK[:child_pid] = pid
            Process.waitpid pid
            BEANPICKER_FORK[:child_pid] = nil
          else
            Process.waitpid pid
          end
          @fork_every_pid = nil
        else
          blk.call
        end
      end

      def running?
        @run
      end

      def die!
        @run = false
        @loop.kill if @loop and @loop.alive?

        kill_pid = nil
        if @fork_master
          kill_pid = @fork_master_pid
        elsif @fork_every
          kill_pid = @fork_every_pid
        end

        if kill_pid and kill_pid.is_a?(Integer) and Process.running?(kill_pid)
          debug "Killing child with pid #{kill_pid}"
          Process.kill "TERM", kill_pid
        end

      end

      def fork_master_child_and_monitor
        @fork_master_pid = Kernel.fork do
          at_exit_to_master_child_fork
          Process.die_with_parent
          BEANPICKER_FORK[:child_master] = true
          $0 = "Beanpicker master child #{@job_name}##{@number}"
          work_loop(self)
        end
        @loop = Thread.new(self) do |child|
          Process.waitpid @fork_master_pid
          child.fork_master_child_and_monitor if child.running?
        end
      end

      def at_exit_to_master_child_fork
        at_exit do
          pid = BEANPICKER_FORK[:child_pid]
          if pid and pid > 0
            if Process.running?(pid)
              Process.kill "TERM", pid
              sleep 0.1
              if Process.running?(pid)
                sleep 2
                Process.kill "KILL", pid if Process.running?(pid)
              end
            end
          end
          Kernel.exit!
        end
      end

      def at_exit_to_every_child_fork
        at_exit do
          Thread.new do
            sleep 1
            Kernel.exit!
          end
          BEANPICKER_FORK[:job].bury rescue nil if BEANPICKER_FORK[:job]
        end
      end

      def log_handler
        #'@log_handler || ' go to worker/global log_handler even if @log_handler is defined
        defined?(@log_handler) ? @log_handler : @worker.nil? ? Beanpicker::log_handler : @worker.log_handler
      end

    end

  end

end

# kill childs or stop jobs
at_exit do
  if not BEANPICKER_FORK[:child_master] and not BEANPICKER_FORK[:child_every]
    Beanpicker::debug "Laying off workers..." if Beanpicker::workers.count > 0
    Beanpicker::stop_workers
  end
end

# hide errors throwed with ctrl+c
trap("INT") {
  exit
}
