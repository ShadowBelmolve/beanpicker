require 'spec_helper'

describe Beanpicker do

  before(:all) do
    Beanpicker::default_fork_every = false
    Beanpicker::default_fork_master = false
  end

  before(:each) do
    @beanstalk = Beanpicker::beanstalk
    @ms = { :values => {}, :methods => [:default_fork_every,
                                       :default_fork_master,
                                       :fork_every,
                                       :fork_master,
                                       :default_childs_number] }
    for m in @ms[:methods]
      @ms[:values][m] = Beanpicker.send(m)
    end

    Thread.stub!(:new)
    Kernel.stub!(:fork)
    Process.stub!(:waitpid)
  end

  after(:each) do
    for m in @ms[:methods]
      Beanpicker.send("#{m}=", @ms[:values][m])
    end
    Beanpicker::workers.replace []
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
      Beanpicker::default_childs_number = 10
      Beanpicker::default_childs_number.should be_equal(10)
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

  describe Beanpicker::Worker do

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


    def c(*a, &blk)
      Beanpicker::Worker::Child.new(*a, &blk)
    end

    context "Child.process"do

      it "should create one child by default" do
        Beanpicker::Worker::Child.process("foo").count.should be_equal(1)
      end

      it "should respect default_childs_number if no option :childs is passed" do
        Beanpicker::default_childs_number = 3
        Beanpicker::Worker::Child.process("foo").count.should be_equal(3)
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

      it "should understand :fork_every and :fork_master" do
        c = c("foo", { :fork_every => true, :fork_master => true })
        c.fork_every.should be_true
        c.fork_master.should be_true
      end

      it "should overwrite :fork_every and :fork_master with :fork" do
        c1 = c("foo", { :fork_every => false, :fork_master => true, :fork => :every })
        c2 = c("foo", { :fork_every => true, :fork_master => false, :fork => :master })
        c1.fork_every.should be_true
        c1.fork_master.should be_false
        c2.fork_every.should be_false
        c2.fork_master.should be_true
      end

      it "should create it own log_handler if :log_file is passed and is a String or a IO" do
        l = Logger.new STDOUT
        Beanpicker.should_receive(:log_handler).exactly(0).times
        c1=c("foo", { :log_file => l })
        c2=c("foo", { :log_file => "/dev/null" })
        c1.log_handler.should be_equal(l)
        c2.log_handler
      end

    end

    it "should watch only the tube with job_name" do
      c = c("foo")
      b = c.beanstalk
      b.watch("bar")
      b.should_receive(:watch).with("foo")
      b.should_receive(:ignore).with("bar")
      c.start_watch
    end

    context "start_loop" do

      it "should call fork_master_child_and_monitor if have fork_master" do
        c=c("foo", :fork_master => true)
        c.should_receive(:fork_master_child_and_monitor)
        c.start_loop
      end

      it "should call Thread.new if haven't fork_master" do
        Thread.should_receive(:new)
        c=c("foo", :fork_master => false)
      end

    end

    context "fork" do

      it "should call Kernel.fork if have fork_every" do
        c=c("foo", :fork_every => true)
        Kernel.should_receive(:fork).once.and_return(0)
        c.fork {}
      end

      it "should call only block if haven't fork_every" do
        c=c("foo", :fork_every => false)
        b = proc {}
        Kernel.should_receive(:fork).exactly(0).times
        b.should_receive(:call).once
        c.fork(&b)
      end

    end

    context "start_work" do

      before(:each) do
        @beanstalk.yput({ :args => { :foo => :bar }})
        @job = @beanstalk.reserve
      end

      it "should reserve and delete a job" do
        c=c("foo"){}
        c.beanstalk.should_receive(:reserve).once.and_return(@job)
        @job.should_receive(:ybody).once.and_return({})
        @job.should_receive(:delete).once
        c.should_receive(:fatal).exactly(0).times
        c.start_work
      end

      it "should bury the job if got a eror" do
        c=c("foo"){ raise RuntimeError }
        @job.should_receive(:delete).exactly(0).times
        @job.should_receive(:bury).once
        c.beanstalk.should_receive(:reserve).and_return(@job)
        Thread.should_receive(:new).once.with(@job).and_yield(@job)
        c.start_work
      end

      it "should not do chain jobs if receive false from block" do
        c=c("foo"){ false }
        @job.ybody[:next_jobs] = ["foo"]
        Beanpicker.should_receive(:enqueue).exactly(0).times
        c.beanstalk.should_receive(:reserve).and_return(@job)
        c.start_work
      end

      it "should not do chain jobs if receive nil from block" do
        c=c("foo"){ nil }
        @job.ybody[:next_jobs] = ["foo"]
        Beanpicker.should_receive(:enqueue).exactly(0).times
        c.beanstalk.should_receive(:reserve).and_return(@job)
        c.start_work
      end

      it "should do chain jobs if receive a positive return from block" do
        c=c("foo"){ true }
        @job.ybody[:next_jobs] = ["foo"]
        Beanpicker.should_receive(:enqueue).once.with(@job.ybody[:next_jobs], @job.ybody[:args])
        c.beanstalk.should_receive(:reserve).and_return(@job)
        c.start_work
      end

      it "should do chain jobs with merged args if receive a hash from block" do
        c=c("foo"){ { :lol => :bar } }
        @job.ybody[:next_jobs] = ["foo"]
        Beanpicker.should_receive(:enqueue).once.with(@job.ybody[:next_jobs], hash_including(@job.ybody[:args].merge({ :lol => :bar })))
        c.beanstalk.should_receive(:reserve).and_return(@job)
        c.start_work
      end

    end

    context "die!" do

      it "should call Process.kill if have a forked child" do
        pending "with die! call it two times Oo"
        c=c("foo", { :fork_every => true }){}
        Kernel.should_receive(:fork).once.and_return(1234)
        Process.should_receive(:waitpid).once.with { c.die!; 1234 }
        Process.should_receive(:running?).once.with(1234).and_return(true)
        Process.should_receive(:kill).once.with("TERM", 1234)
        c.fork
      end

      it "should not call Process.kill if haven't a forked child" do
        c=c("foo", { :fork_every => false }){}
        Process.should_receive(:running?).exactly(0).times
        Process.should_receive(:kill).exactly(0).times
        c.fork { c.die! }
      end

    end

    context "fork_master_child_and_monitor"
    context "at_exit_to_master_child"
    context "at_exit_to_every_child_fork"

    context "log_handler" do

      it "should call worker log_handler if haven't it own" do
        worker = mock("Worker")
        worker.should_receive(:log_handler).and_return(123)
        Beanpicker.should_receive(:log_handler).exactly(0).times
        c=c("foo", {}, 0, worker)
        c.log_handler.should be_equal(123)        
      end

      it "should call Beanpicker::log_handler if haven't it own nor worker" do
        Beanpicker.should_receive(:log_handler).and_return(123)
        c("foo").log_handler.should be_equal(123)
      end

      it "should call it own log_handler if exists" do
        Beanpicker.should_receive(:log_handler).exactly(0).times
        c=c("foo")
        c.log_handler = STDOUT
        c.log_handler
      end

    end

  end

end

