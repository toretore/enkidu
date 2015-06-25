require 'securerandom'
require 'thread'


module Enkidu




  # The Dispatcher maintains a queue of callable objects that are run in the order
  # they get added. When there is nothing in the queue, it blocks the thread.
  #
  # Operations on the Dispatcher are thread-safe.
  #
  # If you do not want to block the current thread, check ThreadedDispatcher.
  #
  #   d = Dispatcher.new
  #   d.schedule{ puts "hello from the scheduler" }
  #   d.schedule{ puts "i will run after the first one" }
  #   d.on('event'){|arg| puts arg } #Add a handler for 'event'
  #   d.on(/[ea]v[ea]nt/){|*a| puts "handling 'event' or 'avant'" }
  #
  #   Thread.new{ sleep 5; d.stop } #Stop the dispatcher after 5 seconds
  #
  #   d.signal 'event', 'argument here' #Signalling doesn't actually run handlers, just schedules them
  #   d.run #Blocks
  class Dispatcher

    RUNNING = :running
    STOPPED = :stopped

    class STOP
      def initialize(callable=nil)
        @callable = callable
      end
      def call(*a)
        @callable && @callable.call(*a)
      end
    end

    attr_reader :state


    def initialize
      @lock = Mutex.new
      @queue = []
      @handlers = []
      @r, @w = IO.pipe
      @state = STOPPED
      yield self if block_given?
    end


    def running?
      state == RUNNING
    end

    def stopped?
      state == STOPPED
    end


    # Run the loop. This will block the current thread until the loop is stopped.
    def run
      @state = RUNNING
      loop do
        IO.select [@r]
        if vals = sync{ @r.read(1); queue.shift }
          callable, args = *vals
          if callable.is_a?(STOP)
            @state = STOPPED
            callable.call(*args)
            break
          else
            callable.call(*args)
          end
        end
      end
    end


    # Schedule a callable to be run. This will push the callable to the back of
    # the queue, so anything scheduled before it will run first.
    #
    #   schedule{ puts "I have been called" }
    #   callable = ->(arg){ p arg }
    #   schedule('an argument', callable: callable)
    def schedule(*args, callable: nil, &b)
      callable = callable(callable, b)
      sync do
        queue.push [callable, args]
        @w.write '.' #TODO Figure out what to do when this blocks (pipe is full); lock will not be released
      end
    end
    alias push schedule

    # Schedule a callable to be run immediately by putting it at the front of the queue.
    #
    #   schedule{ puts "Hey, that's not nice :(" }
    #   unshift{ puts "Cutting in line" }
    def unshift(*args, callable: nil, &b)
      callable = callable(callable, b)
      sync do
        queue.unshift [callable, args]
        @w.write '.'
      end
    end


    # Stop the dispatcher. This schedules a special STOP signal that will stop the
    # dispatcher when encountered. This means that all other items that were scheduled
    # before it will run first.
    #
    # This action is idempotent; it returns true if the dispatcher is currently running
    # and will be stopped, false if it's already stopped.
    def stop(callable: nil, &b)
      callable ||= b
      if stopped?
        callable && callable.call
        false
      else
        schedule(callable: STOP.new(callable))
        true
      end
    end

    # Stop the dispatcher immediately by scheduling the stop action at the front of the
    # queue. This means that any other already scheduled items will be ignored.
    #
    # This action is idempotent; it returns true if the dispatcher is currently running
    # and will be stopped, false if it's already stopped.
    def stop!(callable: nil, &b)
      callable ||= b
      if stopped?
        callable && callable.call
        false
      else
        unshift(callable: STOP.new(callable))
        true
      end
    end


    # Signal an event
    #
    # If a handler is found that matches the given type, it is scheduled to be executed
    #
    # `type` is =~ against each handler's regex, each handler that matches is scheduled
    #
    #   signal 'foo.bar.baz', arg1, arg2
    #   signal ['foo', 'bar', 'baz'], arg1, arg2 #Same as above
    def signal(type, *args)
      type = type.join('.') if Array === type
      0.upto(handlers.size - 1).each do |index|
        if vals = sync{ handlers[index] }
          regex, handler = *vals
          if regex =~ type
            schedule(*args, callable: handler)
          end
        end#if vals
      end#each
    end


    # Add an event handler. The given callable will be scheduled when an event
    # matching `type` is `signal`ed.
    #
    # The `type` is either:
    #
    #   * A Regexp: For each signalled event, `type` will be =~ against the
    #               event, and the callable scheduled on a match.
    #
    #   * A String: The string will be converted to a Regexp that matches
    #               using the same rules as AMQP-style subscriptions:
    #
    #                 * foo.bar.baz.quux
    #                 * foo.*.baz.quux
    #                 * foo.#.quux
    #
    #   * An Array: The elements of the array are joined with a '.', and the
    #               resulting string is used as above.
    def add_handler(type, callable=nil, &b)
      callable = callable(callable, b)
      regex = regex_for(type)
      sync do
        handlers << [regex, callable]
      end
    end
    alias on add_handler


    def add(source, name=nil)
      source = source.new(self) if Class === source
      sync do
        define_singleton_method name do
          source
        end if name
      end
    end


    def self.run(*a, &b)
      d = new(*a, &b)
      d.run
      d
    end


  private

    # Convert an AMQP-style pattern into a Regexp matching the same strings.
    #
    #   ['foo', 'bar', 'baz'] => /\Afoo\.bar\.baz\Z/     #foo.bar.baz
    #   ['foo', '*', 'baz']   => /\Afoo\.[^\.]+\.baz\Z/  #foo.*.baz
    #   ['foo', '#', 'baz']   => /\Afoo\..*?\.baz\Z/     #foo.#.baz
    #
    # A string will be split('.') first, and a RegExp returned as-is.
    def regex_for(pattern)
      return pattern if Regexp === pattern
      pattern = pattern.split('.') if String === pattern

      source = ''
      pattern.each_with_index do |part, index|
        if part == '*'
          source << '\\.' unless index == 0
          source << '[^\.]+'
        elsif part == '#'
          source << '.*?' # .*?  ?
        else
          source << '\\.' unless index == 0
          source << part
        end
      end

      Regexp.new("\\A#{source}\\Z")
    end

    def synchronize
      @lock.synchronize do
        yield
      end
    end
    alias sync synchronize

    def handlers
      @handlers
    end

    def queue
      @queue
    end

    def callable(*cs)
      cs.each do |c|
        return c if c
      end
      raise ArgumentError, "No callable detected"
    end

  end




  class ThreadedDispatcher < Dispatcher

    attr_reader :thread


    def run
      running = false
      schedule{ running = true }
      @thread = Thread.new do
        super
      end
      sleep 0.01 until running
      @thread.abort_on_exception = true
      @thread
    end


    def join(*a)
      @thread.join(*a)
    end

    def wait(*a)
      stop
      join(*a)
    end


  end#class ThreadedDispatcher




end#module Enkidu
