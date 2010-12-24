# Beanpicker

## What is it?

Beanpicker is a job queueing DSL for Beanstalk

## What? Beanstalk? It make coffe?

[beanstalk(d)][beanstalk] is a fast, lightweight queueing backend inspired by mmemcached. The Ruby Beanstalk client is a bit raw, however, so Beanpicker provides a thin wrapper to make job queueing from your Ruby app easy and fun.

## Is this similar to Stalker?

Yes, it is inspired in [stalker][stalker] and in [Minion][minion]

### Why should I use Beanpicker instead of Stalker?

Beanpicker work with subprocess. It create a fork for every request and destroy it in the end.

The vantages of Beanpicker are:
* Your job can use a large amount of RAM, it will be discarted when it end
* You can change vars in jobs, they will not be changed to other jobs nor the principal process
* If all your jobs need a large lib to be loaded(Rails?), you load it once in principal process and it will be available to all jobs without ocupping extra RAM
* It use YAML instead of JSON, so you can pass certain Ruby Objects(Time, Date, etc) //Please, don't try to pass a Rails Model or anything similar, pass only the ID so the job can avoid a possible outdated object

## Queueing jobs

From anywhere in your app:

    require 'beanpicker'

    Beanpicker.enqueue('email.send', :to => 'joe@example.com')
    Beanpicker.enqueue('post.cleanup.all')
    Beanpicker.enqueue('post.cleanup', :id => post.id)

### Chain jobs

If you have a task that requires more than one step just pass an array of queues when you enqueue.

    require 'beanpicker'

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

Beanpicker look in ENV variables BEANSTALK_URL and BEANSTALK_URLS.
In _URL it expect a url like "server[:port]" or "beanstalk://server[:port]".
In _URLS it expect a list of urls separed by comma. e.g. "localhost,localhost:11301,10.1.1.9,10.1.1.10:3000"

## Credits

Created by [Renan Fernandes][renan-website]

Released under the [MIT License][license]

[beanstalk]: http://kr.github.com/beanstalkd/ "Beanstalk" 
[stalker]: http://github.com/adamwiggins/stalker "Stalker"
[minion]: http://github.com/orionz/minion "Minion"
[license]: http://www.opensource.org/licenses/mit-license.php "MIT License"
[renan-website]: http://renanfernandes.com.br "Author's Website"
