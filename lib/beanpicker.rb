require 'rubygems'
require 'beanstalk-client'
require 'uri'
require 'logger'

$:.unshift( File.expand_path(File.dirname(__FILE__)) )

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
      if v.is_a?(String)
        @log_handler = ::Logger.new(v)
      else
        for m in [:debug, :info, :warn, :error, :fatal]
          unless v.respond_to?(m)
            error "Logger #{v} don't respond to #{m}. Ignoring!"
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
    if jobs.is_a?(Array)
      raise ArgumentError, "you need at least 1 job" if jobs.empty?
      job = jobs.shift
    else
      job = jobs.to_s
      jobs = []
    end

    beanstalk.use(job)
    beanstalk.yput({ :args => args, :next_jobs => jobs}, *opts)
  rescue Beanstalk::NotConnected => e
    exception_message(e, "You have a problem with beanstalkd.\nIs it running?")
    @@beanstalk = new_beanstalk
  end

  def beanstalk
    @@beanstalk ||= new_beanstalk
  end

  def new_beanstalk
    Beanstalk::Pool.new(beanstalk_urls)
  end

  def beanstalk_urls
    urls = [ENV['BEANSTALK_URL'], ENV['BEANSTALK_URLS']].compact.join(",").split(",") do |url|
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

  def default_fork
    defined?(@@default_fork) ? @@default_fork : true
  end

  def default_fork=(v)
    @@default_fork = !!v
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
  end
end
