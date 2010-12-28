require 'rubygems'
require 'beanstalk-client'
require 'uri'
require 'logger'

$:.unshift( File.expand_path(File.dirname(__FILE__)) )

require 'beanpicker/version'

module Beanpicker

  extend self

  module MsgLogger

    def debug(m)
      log_handler.debug msg(m)
    end

    def info(m)
      log_handler.info msg(m)
    end

    def warn(m)
      log_handler.warn msg(m)
    end

    def error(m)
      log_handler.error msg(m)
    end

    def fatal(m)
      log_handler.fatal msg(m)
    end
       
    def msg(msg)
      if @name
        "[#{name}] #{msg}"
      else
        msg
      end
    end

    def log_handler
      @log_handler ||= ::Logger.new(STDOUT)
    end

    def log_handler=(v)
      if [String, IO].include?(v.class)
        @log_handler = ::Logger.new(v)
      else
        for m in [:debug, :info, :warn, :error, :fatal]
          unless v.respond_to?(m)
            error "Logger #{v} don't respond to #{m}. Aborting!"
            return
          end
        end
        @log_handler = v
      end
    end

  end

  extend MsgLogger

  def enqueue(jobs, args={}, o={})
    opts = [
      o[:pri]   || default_pri,
      o[:delay] || default_delay,
      o[:ttr]   || default_ttr
    ]

    jobs = [jobs.to_s] unless jobs.is_a?(Array)
    jobs.compact!
    raise ArgumentError, "you need at least 1 job" if jobs.empty?
    job = jobs.first

    beanstalk.use(job)
    beanstalk.yput({ :args => args, :next_jobs => jobs[1..-1]}, *opts)
  rescue Beanstalk::NotConnected => e
    raise e if defined?(r)
    r = true
    error exception_message(e, "You have a problem with beanstalkd.\nIs it running?")
    @@beanstalk = new_beanstalk
    retry
  end

  def beanstalk
    @@beanstalk ||= new_beanstalk
  end

  def new_beanstalk
    Beanstalk::Pool.new(beanstalk_urls)
  end

  def beanstalk_urls
    urls = [ENV['BEANSTALK_URL'], ENV['BEANSTALK_URLS']].compact.join(",").split(",").map do |url|
      if url =~ /^beanstalk:\/\//
        uri = URI.parse(url)
        url = "#{uri.host}:#{uri.port}"
      else
        url = url.gsub(/^([^:\/]+)(:(\d+)).*$/) { "#{$1}:#{$3 || 11300}" }
      end
      url =~ /^[^:\/]+:\d+$/ ? url : nil
    end.compact
    urls.empty? ? ["localhost:11300"] : urls
  end

  def exception_message(e, msg=nil)
    m = []
    m << msg if msg
    m << e.message
    m += e.backtrace
    m.join("\n")
  end

  def default_pri
    @@default_pri ||= 65536
  end

  def default_pri=(v)
    @@default_pri = v
  end

  def default_delay
    @@default_delay ||= 0
  end

  def default_delay=(v)
    @@default_delay = v
  end

  def default_ttr
    @@default_ttr ||= 120
  end

  def default_ttr=(v)
    @@default_ttr = v
  end

  def default_childs_number
    @@default_childs_number ||= 1
  end

  def default_childs_number=(v)
    @@default_childs_number = v
  end

  def default_fork_every
    defined?(@@default_fork_every) ? @@default_fork_every : true
  end

  def default_fork_every=(v)
    @@default_fork_every = !!v
  end

  def default_fork_master
    defined?(@@default_fork_master) ? @@default_fork_master : false
  end

  def default_fork_master=(v)
    @@default_fork_master = !!v
  end

  def fork_every
    defined?(@@fork_every) ? @@fork_every : nil
  end

  def fork_every=(v)
    @@fork_every = !!v
  end

  def fork_master
    defined?(@@fork_master) ? @@fork_master : nil
  end

  def fork_master=(v)
    @@fork_master = !!v
  end

  def workers
    @@workers ||= []
  end

  def add_worker(worker)
    workers << worker
  end

  def stop_workers
    for worker in workers
      for child in worker.childs
        child.die!
      end
    end
    workers.clear
  end
end
