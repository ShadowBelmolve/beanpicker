require 'rubygems'
require 'rake'

require File.expand_path("../lib/beanpicker/version", __FILE__)

begin
  require 'jeweler'
  Jeweler::Tasks.new do |gem|
    gem.name        = "beanpicker"
    gem.summary     = "DSL for beanstalkd, similar to Stalker/Minion"
    gem.description = "DSL for beanstalkd, similar to Stalker/Minion but uses subprocesses"
    gem.email       = "renan@kauamanga.com.br"
    gem.homepage    = "http://github.com/ShadowBelmolve/beanpicker"
    gem.authors     = ["Renan Fernandes"]
    gem.license     = "MIT"
    gem.version     = Beanpicker::VERSION_STRING
    gem.add_dependency "beanstalk-client"
    gem.add_development_dependency "rspec", ">= 2.0"
    gem.executables = ["combine"]


  end
  Jeweler::GemcutterTasks.new
  Jeweler::RubygemsDotOrgTasks.new
rescue LoadError
  puts "Jeweler (or a dependency) not available. Install it with: gem install jeweler"
end


desc "Run the tests with RSpec"
task :test do
  require 'rspec/autorun'
  ARGV.clear
  ARGV << "spec"
end

task :default => :test

require 'rake/rdoctask'
Rake::RDocTask.new do |rdoc|

  rdoc.rdoc_dir = 'doc'
  rdoc.title = "Beanpicker #{Beanpicker::VERSION_STRING}"
  rdoc.rdoc_files.include('README*')
  rdoc.rdoc_files.include('lib/**/*.rb')
end

