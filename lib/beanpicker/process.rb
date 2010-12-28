# Process Premium Version + Crack + Serial + two new methods
module Process

  # Verify if a process is running
  def self.running?(pid)
    begin
      Process.kill 0, pid
      return true
    rescue Errno::ESRCH, Errno::EPERM
      return false
    end
  end

  # Create a thread to kill the current process if the parent process die
  def self.die_with_parent
    Thread.new do
      while Process.running?(Process.ppid)
        sleep 1
      end
      Kernel.exit
    end
  end
end
