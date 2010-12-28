require 'rubygems'
require 'beanstalk-client'
require 'uri'
require 'logger'

$:.unshift( File.expand_path(File.dirname(__FILE__)) )

require 'beanpicker/version'

# The fucking master job DSL to beanstalkd
#
# Just use it and go to beach ;)
module Beanpicker

  extend self

  # Abstract logger methods
  module MsgLogger

    # call .debug of logger
    def debug(m)
      log_handler.debug msg(m)
    end

    # call .info of logger
    def info(m)
      log_handler.info msg(m)
    end

    # call .warn of logger
    def warn(m)
      log_handler.warn msg(m)
    end

    # call .error of logger
    def error(m)
      log_handler.error msg(m)
    end

    # call .fatal of logger
    def fatal(m)
      log_handler.fatal msg(m)
    end
       
    # prepare the message for logger
    def msg(msg)
      if @name
        "[#{name}] #{msg}"
      else
        msg
      end
    end

    # return the current logger os create a new
    def log_handler
      @log_handler ||= ::Logger.new(STDOUT)
    end

    # set a new logger
    # if the argument is a String/IO it will create a new instance of Logger using it argument
    # else it will see if the argument respond to debug, info, warn, error and fatal
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

  # Send a new queue to beanstalkd
  #
  # The first argument is a String with the name of job or a Array of Strings to do job chains
  # 
  # The second argument should be any object that will be passed in a YAML format to the job
  #
  # The third argument should be a hash containing :pri(priority) => Integer, :delay => Integer and :ttr(time-to-work) => Integer
  #
  # If beanstalk raise a Beanstalk::NotConnected, enqueue will create a new instance of beanstalk connection and retry.
  # If it raise again, enqueue will raise the error
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

  # Return the default beanstalk connection os create a new one with new_beanstalk
  def beanstalk
    @@beanstalk ||= new_beanstalk
  end

  # Create a new beanstalk connection using the urls from beanstalk_urls
  def new_beanstalk
    Beanstalk::Pool.new(beanstalk_urls)
  end

  # Look in ENV['BEANSTALK_URL'] and ENV['BEANSTALK_URLS'] for beanstalk urls and process returning a array.
  #
  # If don't find a good url it will return a array with just "localhost:11300"(default beanstalk port)
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

  # Helper to should a exception message
  def exception_message(e, msg=nil)
    m = []
    m << msg if msg
    m << e.message
    m += e.backtrace
    m.join("\n")
  end

  # Return the default priority(65536 by default).
  #
  # This is used by enqueue
  def default_pri
    @@default_pri ||= 65536
  end

  # Set the default priority
  def default_pri=(v)
    @@default_pri = v
  end

  # Return the default delay(0 by default)
  #
  # This is used by enqueue
  def default_delay
    @@default_delay ||= 0
  end

  # Set the default delay
  def default_delay=(v)
    @@default_delay = v
  end

  # Set the default time-to-work(120 by default)
  #
  # This is used by enqueue
  def default_ttr
    @@default_ttr ||= 120
  end

  # Set the default time-to-work
  def default_ttr=(v)
    @@default_ttr = v
  end

  # Return the default number of childs that a Worker should create(1 by default)
  #
  # This is used by Worker::Child.process
  def default_childs_number
    @@default_childs_number ||= 1
  end

  # Set the default childs number
  def default_childs_number=(v)
    @@default_childs_number = v
  end

  # Return if a child should fork every time that a job will process.
  # This option is overwrited by job options and fork_every
  #
  # This is used by Worker::Child
  def default_fork_every
    defined?(@@default_fork_every) ? @@default_fork_every : true
  end

  # Set the default_fork_every
  def default_fork_every=(v)
    @@default_fork_every = !!v
  end

  # Return if a child should fork itself on intialize.
  # This should be used when default_fork_every is false.
  # This option is overwrited by job options and fork_master
  #
  # Use it only if the jobs need high speed and are "memory leak"-safe
  #
  # This is used by Worker::Child
  def default_fork_master
    defined?(@@default_fork_master) ? @@default_fork_master : false
  end

  # Set the default_fork_master
  def default_fork_master=(v)
    @@default_fork_master = !!v
  end

  # See default_fork_every
  #
  # This option overwrite all others
  def fork_every
    defined?(@@fork_every) ? @@fork_every : nil
  end

  # Set the fork_every
  def fork_every=(v)
    @@fork_every = v.nil? ? nil : !!v
  end

  # See default_fork_master
  #
  # This option overwrite all others
  def fork_master
    defined?(@@fork_master) ? @@fork_master : nil
  end

  # Set the fork_master
  def fork_master=(v)
    @@fork_master = v.nil? ? nil : !!v
  end

  # Return a Array with the workers registered
  def workers
    @@workers ||= []
  end

  # Add a worker to the list of workers
  def add_worker(worker)
    workers << worker
  end

  # Call die! for all childs of every worker and clear the list
  # See workers
  def stop_workers
    for worker in workers
      for child in worker.childs
        child.die!
      end
    end
    workers.clear
  end
end
