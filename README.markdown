# Beanpicker

## What is it?

Beanpicker is a job queueing DSL for Beanstalk

## What? Beanstalk? It make coffe?

[beanstalk(d)][beanstalk] is a fast, lightweight queueing backend inspired by memcached. The Ruby Beanstalk client is a bit raw, however, so Beanpicker provides a thin wrapper to make job queueing from your Ruby app easy and fun.

## Is this similar to Stalker?

Yes, it is inspired in [stalker][stalker] and in [Minion][minion]

### Why should I use Beanpicker instead of Stalker?

Beanpicker work with subprocess. It create a fork for every request and destroy it in the end.

The vantages of Beanpicker are:

*  Your job can use a large amount of RAM, it will be discarted when it end
*  You can change vars in jobs, they will not be changed to other jobs nor the principal process
*  If all your jobs need a large lib to be loaded(Rails?), you load it once in principal process and it will be available to all jobs without ocupping extra RAM
*  It use YAML instead of JSON, so you can pass certain Ruby Objects(Time, Date, etc) //Please, don't try to pass a Rails Model or anything similar, pass only the ID so the job can avoid a possible outdated object

### How is his performance?

My machine:

*  Notebook LG 590 5100
*  Processor Intel Core i3 330M
*  4GB RAM DDR3
*  Arch Linux x86-64

The speed with 10000 requests given 'with fork' is :fork => :every and 'without fork' is :fork => :master/false

\# time / requests per second / cpu load

*  MRI 1.9.2
   *  With fork: 117.85 / 84.85 / 100%
   *  Without fork: 4.14 / 2415 / 30%
*  MRI 1.8.7
   *  With fork: 122.27 / 81.78 / 58%
   *  Without fork: 6.34 / 1577 / 30~40%
*  REE 1.8.7
   *  With fork: 121.92 / 82.02 / 20~60%
   *  Without fork: 4.77 / 2096 / 30%
* JRuby 1.5.6 + OpenJDK 6.2b0\_1.9.3 VM 1.6.0\_20
   *  With fork: don't accept fork?
   *  Without fork: 10.99 / 909.91 / 97%
* Rubinius 1.2.0
   *  With fork: don't try, too much errors
   *  Without fork: 11.24 / 889 / 36~52%

Fork is activated by default, it should slow down your application but keep safe from memory leaks.

You can easy active or desactive the fork for a job with:

    job "job.without.fork", :fork => false do |args|
      debug "Running on a thread in main process"
      warn "This process will grow because of any job running on main process"
    end

    job "job.with.fork.every.time", :fork => :every do |args|
      debug "Running on a fork of main process"
      debug "This process will be killed on end of this job"
      debug "This decrease the peformance but save from memory leaks"
      debug "All extra memory used by this process will vanish in end"
    end

    job "job.with.fork.once", :fork => :master do |args|
      debug "Running on a fork of main process"
      debug "This process will not be killed on end of this job"
      debug "This increase the performance but don't save from memory leaks"
      debug "This process will only grow in memory because of code executed in 'job.with.fork.once'"
    end

You can pass :fork\_every => true(default)/false and :fork\_master => true/false(default)

The :fork argument overwrite :fork\_every and :fork\_master

The default :fork\_every and :fork\_master are setted on Beanpicker::default\_fork\_[master|every]

Beanpicker::fork\_every and Beanpicker::fork\_master overwrite the job options, so, if you set they false the jobs will run in the main thread even if they specify the :fork, :fork\_every and/or :fork\_master

## Queueing jobs

From anywhere in your app:

    require 'beanpicker'

    Beanpicker.enqueue('email.send', :to => 'joe@example.com')
    Beanpicker.enqueue('post.cleanup.all')
    Beanpicker.enqueue('post.cleanup', :id => post.id)

### Chain jobs

If you have a task that requires more than one step just pass an array of queues when you enqueue.

    require 'beanpicker/job_server'

    Beanpicker::Worker.new do
      # this is a slow job, so we'll spawn 10 forks of it :)
      job "email.fetch_attachments", :childs => 10 do |args|
        attachment_ids = Email.fetch_attachments_for args[:email_id]
        { :attachment_ids => attachment_ids }
      end
      
      # by default :childs is 1
      job "email.send" do |args|
        Email.send({
          :id => args[:email_id],
          :attachments => args[:attachment_ids].map { |a| Attachment.find(a) }
        })
      end

    end

    Beanpicker.enqueue(["email.fetch_attachments", "email.send"], :email_id => 10)


## Output Messages

Inside of a job you can use debug, info, warn, error and fatal. It will be redirected to logger(STDOUT by default)

## Options

### Global options

All options are inside of module Beanpicker

*   Used for jobs:
   *   Global:
      *   default\_fork\_every: If should fork a job and destroy every time It will run. This options is overwrited by specified job options. Default true
      *   default\_fork\_master: If should fork the child process. This options is overwrited by specified job options. Default false
      *   fork\_every: Like default\_fork\_every, but overwrite job options. Default nil
      *   fork\_master: Like default\_fork\_master, but overwrite job options. Default nil
      *   default\_childs\_number: How much childs should be started for every job? Default 1
   *   In job file(not function):
      *   log\_file : Use a own log file, this file should be used to all jobs, except the ones who specify a :log\_file
   *   In 'job' function:
      *   :fork\_every : Overwrite default\_fork\_every and is overwrited by fork\_every
      *   :fork\_master : Overwrite default\_fork\_master and is overwrited by fork\_master
      *   :fork : Overwrite :fork\_every and :fork\_master, expect :every to every=true and master=false, :master to every=false and master=true or other value(any) to every=false and master=false. The result can be overwrited by fork\_master and fork\_every.
      *   :log\_file : Use a own log file
*   Used for enqueue
   *   Global
      *   default\_pri: The priority of job. Default 65536
      *   default\_delay: The delay to start the job. Default 0
      *   default\_ttr: The time to run the job. Default is 120
   *   In 'enqueue' function
      *   :pri
      *   :delay
      *   :ttr


## Using combine

Beanpicker ships with "combine", "A Beanpicker server"

Try combine --help to see all options

e.g. command:

    combine -r config.rb -l log/jobs.log sandwich_jobs.rb email_jobs.rb


## Multiple Beanstalk servers

Beanpicker look in ENV variables BEANSTALK\_URL and BEANSTALK\_URLS.

In BEANSTALK\_URL it expect a url like "server[:port]" or "beanstalk://server[:port]".

In BEANSTALK\_URLS it expect a list of urls separed by comma. e.g. "localhost,localhost:11301,10.1.1.9,10.1.1.10:3000"

## Credits

Created by [Renan Fernandes][renan-website]

Released under the [MIT License][license]

[beanstalk]: http://kr.github.com/beanstalkd/ "Beanstalk" 
[stalker]: http://github.com/adamwiggins/stalker "Stalker"
[minion]: http://github.com/orionz/minion "Minion"
[license]: http://www.opensource.org/licenses/mit-license.php "MIT License"
[renan-website]: http://renanfernandes.com.br "Author's Website"
