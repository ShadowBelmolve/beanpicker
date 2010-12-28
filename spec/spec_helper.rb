require File.expand_path("../../lib/beanpicker/job_server", __FILE__)

RSpec.configure do |c|
  c.mock_with :rspec
end

Object.send(:remove_const, :TCPSocket)

class TCPSocket

  class FakeBeanstalkSocketErrorGetsWithoutQueue < RuntimeError; end
  class FakeBeanstalkSocketErrorGetsWithSepStringNotMatch < RuntimeError; end
  class FakeBeanstalkSocketErrorReadWithoutQueue < RuntimeError; end
  class FakeBeanstalkSocketErrorReadWithoutCorrectLength < RuntimeError; end
  class FakeBeanstalkSocketErrorCantUnderstandCommand < RuntimeError; end

  def self.instances
    @instances ||= []
  end

  def self.fail
    if fail_times > 0
      true
    else
      false
    end
  end

  def self.fail_times(n=nil)
    @fail_times ||= 0
    if n.nil?
      if @fail_times > 0
        n = @fail_times -=1
        n+1
      else
        0
      end
    else
      @fail_times = n
    end
  end


  attr_reader :host, :port, :_queue, :tube_used, :last_command
  def initialize(h, p)
    raise Errno::ECONNREFUSED if self.class.fail
    @host = h
    @port = p
    @_queue = []
    @tubes = ["default"]
    @tube_used = "default"
    @last_command = ""
    @last_error = ""
    @last_response = ""
    @cmd_i = 0
    @jobs = {}
    self.class.instances << self
  end

  def write(s)
    @last_command = s
    @_queue << case s
    when /^put (\d+) (\d+) (\d+) (\d+)\r\n(.*)\r\n$/m then
      @jobs[@cmd_i+=1] = $5
      "INSERTED #{@cmd_i}\r\n"
    when /^use (.*)\r\n$/ then
      @tube_used = $1
      (@tubes << $1).uniq!
      "USING #{$1}\r\n"
    when /^reserve(-with-timeout \d+)?\r\n/
      n = @jobs.keys.first
      @_queue << "RESERVED #{n} #{@jobs[n].length}\r\n"
      @jobs[n] + "\r\n"
    when /^delete (\d+)\r\n$/ then
      @job.delete $1
      "DELETED\r\n"
    when /^release (\d+) (\d+) (\d+)\r\n$/ then
      "RELEASED\r\n"
    when /^bury (\d+) (\d+)\r\n$/ then
      "BURIED\r\n"
    when /^touch (\d+)\r\n$/ then
      "TOUCHED\r\n"
    when /^watch (.*)\r\n$/ then
      (@tubes << $1).uniq!
      "WATCHING #{@tubes.size}\r\n"
    when /^ignore (.*)\r\n$/ then
      @tubes.select! { |x| x != $1 }
      "WATCHING #{@tubes.size}\r\n"
    when /^list-tubes(-watched)?\r\n$/ then
      y = @tubes.to_yaml
      @_queue << "OK #{y.size}\r\n"
      "#{y}\r\n"
    when /^list-tube-used\r\n$/ then
      "USING #{@tube_used}\r\n"
    else
      raise FakeBeanstalkSocketErrorCantUnderstandCommand, s
    end

    s.length
  end

  def gets(s=nil)
    raise FakeBeanstalkSocketErrorGetsWithoutQueue if @_queue.size == 0
    if s.nil?
      @last_response = @_queue.shift
    else
      if @_queue.join.scan(s).size > 0
        i = 0
        for m in @_queue
          scan = m.scan(/^(.*#{s})(.*)$/m)
          if scan.size == 0
            i += 1
          else
            f = @_queue.shift(i).join
            f << scan[0][0]
            if scan[0][1].empty?
              @_queue.shift
            else
              @_queue[0] = scan[0][1]
            end
            return f
          end
        end
        raise FakeBeanstalkSocketErrorGetsWithSepStringNotMatch, s
      else
        raise FakeBeanstalkSocketErrorGetsWithSepStringNotMatch, s
      end
    end
  end

  def read(n=nil)
    raise FakeBeanstalkSocketErrorReadWithoutQueue if @_queue.size == 0
    raise FakeBeanstalkSocketErrorReadWithoutCorrectLength, n if not n.nil? and @_queue.join.size < n
    sleep 0.1 while not n.nil? and @_queue.join.size < n

    o = ""
    i = 0
    l = 0
    for m in @_queue
      if l + m.length < n
        i += 1
        l += m.length
      else
        o << @_queue.shift(i).join
        if l+m.length == n
          o << @_queue.shift
        else
          s = @_queue.first.scan(/^(.{#{n-l}})(.*)$/m)
          o << s[0][0]
          @_queue[0] = s[0][1]
        end
        @last_response = o
        return o
      end
    end
  end

  def fcntl(*a)
  end

  def close
  end

end

for m in [:debug, :info, :warn, :error, :fatal]
  Logger.module_eval("def #{m}(*a); true; end")
end
