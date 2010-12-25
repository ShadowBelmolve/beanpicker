Process.module_eval do
  def self.running?(pid)
    begin
      Process.kill 0, pid
      return true
    rescue Errno::ESRCH, Errno::EPERM
      return false
    end
  end

  def self.die_with_parent
    Thread.new do
      while Process.running?(Process.ppid)
        sleep 1
      end
      Kernel.exit
    end
  end
end
