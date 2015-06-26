require 'enkidu/dispatcher'
require 'enkidu/tools'
require 'securerandom'
require 'time'

module Enkidu




  class LogSource

    attr_reader :defaults


    def initialize(d, defaults:{})
      @defaults = defaults
      @dispatcher = d
    end


    def log(*args)
      atts = Enkidu.deep_merge(defaults, attify(args))
      path = atts[:type] || atts['type'] || 'log'
      dispatcher.signal(path, atts)
    end

    def info(*args)
      atts = attify(args)
      log(Enkidu.deep_merge({tags: ['INFO']}, atts))
    end

    def error(*args)
      atts = attify(args)
      log(Enkidu.deep_merge({tags: ['ERROR']}, atts))
    end

    def exception(e, *args)
      atts = Enkidu.deep_merge({tags: ['EXCEPTION'], message: "#{e.class}: #{e.message}"}, attify(args))
      atts[:exception] = {type: e.class.name, message: e.message, stacktrace: e.backtrace}
      if e.respond_to?(:cause) && e.cause
        atts[:exception][:cause] = {type: e.cause.class.name, message: e.cause.message, stacktrace: e.cause.backtrace}
      end

      error atts
    end

    def tail(pattern='#', &b)
      dispatcher.on("log.#{pattern}", b)
    end


  private

    def attify(args)
      a = if args[0].is_a?(String)
        args[1] ? {message: args[0]}.merge(args[1]) : {message: args[0]}
      else
        args[0] || {}
      end
      a[:tags] ||= []
      a[:atts] ||= {}
      a
    end

    def dispatcher
      @dispatcher
    end


  end#class LogSource




  class LogSink





    class DefaultFormatter


      def initialize
      end


      def generate_id
        SecureRandom.hex(3)
      end


      def tags(msg)
        return '[] ' unless msg[:tags]
        "[#{msg[:tags].map{|t| escape_tag(t) }.join(', ')}] "
      end


      def attributes(msg)
        return '{} ' unless msg[:atts]
        "{#{msg[:atts].map{|k,v| "#{escape_attr k}=#{escape_attr v}" }.join(', ')}} "
      end


      def message(msg)
        "#{msg[:message]}" +
        (msg[:exception] ? "\n  #{msg[:exception][:type]}: #{msg[:exception][:message]}\n#{msg[:exception][:stacktrace].map{|l| "    #{l}" }.join("\n")}" : '')
      end


      def timestamp
        Time.now.iso8601(3)
      end


      def call(msg)
        id = generate_id
        "<#{id} #{timestamp}> " + tags(msg) + attributes(msg) + message(msg) + " </#{id}>"
      end


      def escape_tag(str)
        "#{str}".gsub(/([\[\],])/, '\\\\\\1')
      end

      def escape_attr(str)
        "#{str}".gsub(/([\{\}=,])/, '\\\\\\1')
      end

    end#class DefaultFormatter




    class HumanFormatter

      def tags(m)
        return '' unless m[:tags] && m[:tags].any?
        tags_separator(m) + m[:tags].map{|t| tag(t) }.join(', ')
      end

      def tag(t)
        if ['ERROR', 'EXCEPTION'].include?(t)
          c [1, 91], t
        else
          c 1, t
        end
      end

      def tags_separator(m)
        " #{c 96, '❯❯'} "
      end


      def atts(m)
        return '' unless m[:atts] && m[:atts].any?
        atts_separator(m) + c(37, m[:atts].map{|k,v| "#{k}: #{v}" }.join(', '))
      end

      def atts_separator(m)
        " #{c 96, '❯❯'} "
      end


      def timestamp(m)
        Time.now.strftime('%H:%M:%S')
      end


      def message(m)
        " ❯❯ #{m[:message]}" +
        (m[:exception] ? "\n  #{c 1, m[:exception][:type]}: #{m[:exception][:message]}\n#{m[:exception][:stacktrace].map{|l| "    #{l}" }.join("\n")}" : '')
      end


      def call(m)
        timestamp(m) + tags(m) + atts(m) + message(m)
      end


      def color(n, s=nil)
        c = Array(n).map{|nn| "\e[0;#{nn}m" }.join
        c << "#{s}\e[0m" if s
        c
      end
      alias c color


      def stop
        "\e[0m"
      end
      alias s stop


    end#class HumanFormatter





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
      @formatter ||= DefaultFormatter.new
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
