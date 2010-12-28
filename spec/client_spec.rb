require 'spec_helper'

describe Beanpicker do

  before(:each) do
    @beanstalk = Beanpicker::beanstalk
    Beanpicker::workers.clear
  end

  context "Getters and Setters" do
    
    describe "log_handler" do

      it "should use STDOUT by default" do
        Logger.should_receive(:new).with(STDOUT).once
        Beanpicker::log_handler
      end

      it "should use string as a argument to Logger" do
        Logger.should_receive(:new).with("/dev/null").once
        Beanpicker::log_handler = "/dev/null"
      end

      it "should use IO as a argument to Logger" do
        Logger.should_receive(:new).with(STDERR).once
        Beanpicker::log_handler = STDERR
      end

      it "should use anything that isn't IO/String and respond to 5 log methods as a logger" do
        l=Logger.new(STDOUT)
        Beanpicker::log_handler = l
        Beanpicker::log_handler.should be_equal(l)
      end

      it "should not use anything that ins't IO/String and don't respond to 5 log methods as a logger" do
        Beanpicker.should_receive(:error).once
        l = Beanpicker::log_handler
        Beanpicker::log_handler = :foo
        Beanpicker::log_handler.should be_equal(l)
      end

    end

    it "default_pri" do
      Beanpicker::default_pri = 10
      Beanpicker::default_pri.should be_equal(10)
    end

    it "default_delay" do
      Beanpicker::default_delay = 10
      Beanpicker::default_delay.should be_equal(10)
    end

    it "default_ttr" do
      Beanpicker::default_ttr = 10
      Beanpicker::default_ttr.should be_equal(10)
    end

    it "default_childs_number" do
      n = Beanpicker::default_childs_number
      Beanpicker::default_childs_number = 10
      Beanpicker::default_childs_number.should be_equal(10)
      Beanpicker::default_childs_number = n
    end

    it "default_fork_every" do
      Beanpicker::default_fork_every = true
      Beanpicker::default_fork_every.should be_true
      Beanpicker::default_fork_every = false
      Beanpicker::default_fork_every.should be_false
    end

    it "default_fork_master" do
      Beanpicker::default_fork_master = true
      Beanpicker::default_fork_master.should be_true
      Beanpicker::default_fork_master = false
      Beanpicker::default_fork_master.should be_false
    end

    it "fork_every" do
      Beanpicker::fork_every = true
      Beanpicker::fork_every.should be_true
      Beanpicker::fork_every = false
      Beanpicker::fork_every.should be_false
    end

    it "fork_master" do
      Beanpicker::fork_master = true
      Beanpicker::fork_master.should be_true
      Beanpicker::fork_master = false
      Beanpicker::fork_master.should be_false
    end

  end

  describe "enqueue" do

    it "should use job name as tube and send via yput" do
      @beanstalk.should_receive(:use).once.with("foo.bar")
      @beanstalk.should_receive(:yput).once.with({ :args => { :foo => :bar }, :next_jobs => [] }, 1, 2, 3)
      Beanpicker.enqueue("foo.bar", { :foo => :bar }, { :pri => 1, :delay => 2, :ttr => 3 })
    end

    it "should use default pri, delay and ttr and argument as a empty hash" do
      @beanstalk.should_receive(:yput).once.with({ :args => {}, :next_jobs => [] },
                                            Beanpicker::default_pri,
                                            Beanpicker::default_delay,
                                            Beanpicker::default_ttr)
      Beanpicker::enqueue("foo.bar")
    end

    it "should understand chain jobs" do
      @beanstalk.should_receive(:yput).once.with({ :args => {}, :next_jobs => ["foo.bar2", "foo.bar3"]}, 1, 2, 3)
      @beanstalk.should_receive(:use).once.with("foo.bar")
      Beanpicker::enqueue(["foo.bar", "foo.bar2", "foo.bar3"], {},
                          { :pri => 1, :delay => 2, :ttr => 3 })
    end

    it "should handle connection error and retry" do
      Beanpicker::beanstalk.should be_equal(@beanstalk)
      @beanstalk.close
      b = Beanpicker::new_beanstalk
      TCPSocket.fail_times(1)
      Beanpicker.should_receive(:new_beanstalk).and_return(b)
      Beanpicker.should_receive(:exception_message).once.with(an_instance_of(Beanstalk::NotConnected), an_instance_of(String))
      Beanpicker.should_receive(:error).once
      Beanpicker.enqueue("foo.bar")
    end

    it "should raise a exeption if a retry don't work" do
      @beanstalk.close
      TCPSocket.fail_times 2
      Beanpicker.should_receive(:error).once
      expect { Beanpicker::enqueue("foo.bar") }.should raise_error(Beanstalk::NotConnected)
      TCPSocket.fail_times 0
    end
    

  end

  context "new beanstalk" do

    it "new_beanstalk should create a new instance of Beanstalk::Pool every time" do
      Beanpicker::new_beanstalk.should_not be_equal(Beanpicker::new_beanstalk)
    end

    it "new_beanstalk_should use beanstalk_urls and return [localhost:11300] by default" do
      Beanpicker::beanstalk_urls.should include("localhost:11300")
      Beanpicker.should_receive(:beanstalk_urls).and_return(["localhost:11300"])
      Beanpicker::new_beanstalk
    end

    it "beanstalk_urls should read ENV['BEANSTALK_URL'] and ENV['BEANSTALK_URLS']" do
      ENV.should_receive(:[]).with("BEANSTALK_URL").and_return("localhost:3000")
      ENV.should_receive(:[]).with("BEANSTALK_URLS").and_return("localhost:1500,beanstalk://www.foo.bar.net:4500")
      urls = Beanpicker::beanstalk_urls
      urls.should include("localhost:3000")
      urls.should include("localhost:1500")
      urls.should include("www.foo.bar.net:4500")
      urls.should_not include("localhost:11300")
    end

  end

  it "add_worker should add a worker(duh!)" do
    expect { Beanpicker::add_worker 1 }.should change(Beanpicker::workers, :size).by(1)
  end

  it "stop_workers should kill childs of workers" do
    child  = mock(Beanpicker::Worker::Child)
    worker = mock(Beanpicker::Worker)
    worker.should_receive(:childs).and_return([child])
    child.should_receive(:die!)
    Beanpicker::workers.should_receive(:clear)
    Beanpicker::add_worker worker
    Beanpicker::stop_workers
  end


end

describe Beanpicker::Worker do

  after(:each) do
    Beanpicker::workers.clear
  end

  it "should handle a error when loading a file" do
    pending "don't know how make"
    Beanpicker::Worker.should_receive(:error)
    Beanpicker::Worker.new("/foo/bar/lol.rb")
  end

  it "should handle a error when evaluating a block" do
    pending "don't know how make"
    Beanpicker::Worker.new do
      foo
    end
  end

  it "should add itself to workers list" do
    expect { Beanpicker::Worker.new }.should change(Beanpicker::workers, :count).by(1)
    Beanpicker::workers.should include(Beanpicker::Worker.new)
  end

  it "job should call Child.process" do
    w=Beanpicker::Worker.new
    Beanpicker::Worker::Child.should_receive(:process).and_return([1])
    expect { w.job("foo.bar") }.should change(w.childs, :count).by(1)
  end

  context "log_handler" do

    it "should use global log_handler if haven't it own defined" do
      l = Logger.new(STDOUT)
      Beanpicker.should_receive(:log_handler).twice.and_return(l)
      l.should_receive(:debug)
      w = Beanpicker::Worker.new
      w.log_handler.should be_equal(l)
      w.debug("foo!")
    end

    it "should use it own log_handler if defined" do
      w=Beanpicker::Worker.new
      w.should_receive(:debug)
      w.log_handler = STDOUT
      w.debug("foo!")
    end

    it "should use log_file as a mirror to log_handler" do
      w=Beanpicker::Worker.new
      w.should_receive(:log_handler=)
      w.log_file 'foo'
    end

  end

end

describe Beanpicker::Worker::Child do

  before(:each) do
    Beanpicker::default_fork_every = false
    Beanpicker::default_fork_master = false
    Thread.stub!(:new)
    Kernel.stub!(:fork)
  end

  after(:each) do
    Beanpicker::workers.clear
  end

  def c(*a)
    Beanpicker::Worker::Child.new(*a)
  end

  context "Child.process"do

    it "should create one child by default" do
      Beanpicker::Worker::Child.process("foo").count.should be_equal(1)
    end

    it "should respect default_childs_number if no option :childs is passed" do
      n = Beanpicker::default_childs_number
      Beanpicker::default_childs_number = 3
      Beanpicker::Worker::Child.process("foo").count.should be_equal(3)
      Beanpicker::default_childs_number = n
    end

    it "should respect :childs if passed" do
      Beanpicker::Worker::Child.process("foo", { :childs => 3 }).count.should be_equal(3)
    end

  end

  context "new" do

    it "should create it own beanstalk instance" do
      b = Beanpicker::new_beanstalk
      Beanpicker.should_receive(:new_beanstalk).and_return(b)
      c("foo", {}, 1)
    end

    it "should define job_name, number and opts and worker" do
      j = "foo"
      n = 1
      o = { :foo => :bar }
      w = mock("Worker")
      child = c(j, o, n, w)
      child.job_name.should be_equal(j)
      child.number.should be_equal(n)
      child.opts.should_not be_equal(o)
      child.opts[:foo].should be_equal(o[:foo])
      child.worker.should be_equal(w)
    end

  end

end
