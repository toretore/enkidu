require 'enkidu/dispatcher'
require 'enkidu/tools'

module Enkidu




  class LogSource

    attr_reader :defaults


    def initialize(d, defaults:{})
      @defaults = defaults
      @dispatcher = d
    end


    def log(atts)
      atts = Enkidu.deep_merge(defaults, atts)
      path = atts[:type] || atts['type'] || 'log'
      dispatcher.signal(path, atts)
    end

    def info(atts)
      log(Enkidu.deep_merge({tags: ['INFO']}, atts))
    end

    def error(atts)
      log(Enkidu.deep_merge({tags: ['ERROR']}, atts))
    end

    def exception(e)
      atts = {tags: ['ERROR', 'EXCEPTION'], message: "#{e.class}: #{e.message}"}
      atts[:exception] = {type: e.class.name, message: e.message, stacktrace: e.backtrace}
      if e.respond_to?(:cause) && e.cause
        atts[:exception][:cause] = {type: e.cause.class.name, message: e.cause.message, stacktrace: e.cause.backtrace}
      end

      log atts
    end

    def tail(pattern='#', &b)
      dispatcher.on("log.#{pattern}", b)
    end


  private

    def dispatcher
      @dispatcher
    end


  end#class LogSource




  class LogSink

    attr_reader :filter

    def initialize(d, io:, filter: 'log.#', formatter: nil)
      @dispatcher = d
      @io = io
      @filter = filter
      @formatter = formatter
      run
    end

    def run
      dispatcher.on filter do |msg|
        log msg
      end
    end

    def log(msg)
      io.puts format(msg)
    end

    def format(msg)
      formatter.call(msg)
    end

    def formatter
      @formatter ||= -> msg do
        (msg[:tags] ? msg[:tags].map{|t| "[#{t}]" }.join+' ' : '') +
        (msg[:atts] ? msg[:atts].map{|k,v| "[#{k}=#{"#{v}"[0,10]}]" }.join+' ' : '') +
        "#{msg[:message]}" +
        (msg[:exception] ? "\n#{msg[:exception][:type]}: #{msg[:exception][:message]}\n#{msg[:exception][:stacktrace].map{|l| "  #{l}" }.join("\n")}" : '')
      end
    end


  private

    def dispatcher
      @dispatcher
    end

    def io
      @io
    end

  end#class LogSink




end#module Enkidu
