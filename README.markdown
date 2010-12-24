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

The speed with 10000 requests # time / requests per second / cpu load

*  MRI 1.9.2
   *  With fork: 117.85 / 84.85 / 100%
   *  Without fork: 4.14s / 2415 / 30%
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

Fork is activated by default, it should slow down your application but keep safe of memory leaks.

You can easy active or desactive the fork for a job with:

    job "job.without.fork", :fork => false do |args|
      debug "Running on a thread in main process"
    end

    job "job.with.fork", :fork => true do |args|
      debug "Running on a fork of main process"
      debug "This process will be killed on end of this job"
    end

The :fork argument overwrite the global Beanpicker::default\_fork


When you need a fucking high speed. Here with raw Beanstalk(beanstalk-client, not stalker) I can handle 1000 querys in 2s, but with Beanpicker I can handle only 1000 querys in 10s.

The largest reason to this is the fork that consume some time.

So think, if you need a extreme high response time, you shouldn't use Beanpicker, but if you need at maximum a high(100 times per second?) response time and a more stable memory management you can use Beanpicker

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
