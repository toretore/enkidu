$:.push File.expand_path("../lib", __FILE__)

Gem::Specification.new do |s|
  s.name        = "enkidu"
  s.version     = '0.0.1'
  s.platform    = Gem::Platform::RUBY
  s.summary     = "Enkidu process sidekick"
  s.email       = "toredarell@gmail.com"
  s.description = "Enkidu is a process sidekick"
  s.authors     = ['Tore Darell']

  s.has_rdoc          = false

  s.files             = ['lib/enkidu.rb', 'lib/enkidu/dispatcher.rb', 'lib/enkidu/logging.rb', 'lib/enkidu/signals.rb', 'lib/enkidu/tools.rb']
  s.require_paths     = ["lib"]

end
