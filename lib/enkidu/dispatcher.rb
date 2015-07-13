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

    class StateError < StandardError; end

    RUNNING = :running
    STOPPED = :stopped

    class STOP
      attr_reader :callback, :cleanup
      alias cleanup? cleanup
      def initialize(callback:nil, cleanup:true)
        @callback = callback
        @cleanup = cleanup
      end
      def call(*a)
        @callback && @callback.call(*a)
      end
    end

    attr_reader :state


    def initialize
      @lock = Mutex.new
      @queue = []
      @handlers = []
      @sources = []
      @handler_serial = -1
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
      raise StateError, "Dispatcher is already running" if running?
      @state = RUNNING
      loop do
        IO.select [@r]
        if vals = sync{ @r.read(1); queue.shift }
          callable, args = *vals
          if callable.is_a?(STOP)
            if callable.cleanup?
              sources.each do |source|
                source.stop if source.respond_to?(:stop)
              end
            end
            callable.call(*args)
            @state = STOPPED
            break
          else
            callable.call(*args)
          end
        end
      end
    end

    # Runs the loop in the same manner as `run`, but will only execute any already
    # scheduled (as in scheduled before the call to `run_once`) callables and then stop.
    #
    #   d = Dispatcher.new
    #   d.schedule{ puts "hello" }
    #   d.run_once #Runs the 1 scheduled callable above and returns
    def run_once(&b)
      schedule_stop(callback: b)
      run
    end


    def schedule_stop(o={}, &b)
      o[:callback] ||= b
      schedule(callable: STOP.new(o))
    end

    def unshift_stop(o={}, &b)
      o[:callback] ||= b
      unshift(callable: STOP.new(o))
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

    # Schedule multiple callables at once
    #
    # Takes an array of [callable, args, position] arrays. args defaults to [], position to :back
    # All callables are guaranteed to be added to the scheduler atomically; that is, neither of
    # the passed callables nor any already scheduled callables will run until they have all been
    # scheduled.
    #
    # The array bundles are processed in the order they appear in the array, so each callable
    # will be added either at the back (default) or the front in that order.
    #
    #   #               Note: the :back here is unnecessary:
    #   schedule_multiple([[->(msg){ puts msg }, ['hello'], :back], [->{ puts "I will run first" }, [], :front], [->{ puts "I will run last" }, []]])
    def schedule_multiple(bundles)
      sync do
        bundles.each do |callable, args=[], position=:back|
          if position == :front
            queue.unshift [callable, args]
          else
            queue.push [callable, args]
          end
          @w.write '.'
        end
      end
    end


    # Stop the dispatcher. This schedules a special STOP signal that will stop the
    # dispatcher when encountered. This means that all other items that were scheduled
    # before it will run first.
    #
    # This action is idempotent; it returns true if the dispatcher is currently running
    # and will be stopped, false if it's already stopped.
    #
    # A callable can be provided either in the form of the callable: kwarg or a block,
    # which will be called after the dispatcher has stopped (also if dispatcher is already stopped).
    #
    # TODO        |------|
    # All attached sources will have their `stop` method called before shutdown.
    def stop(callable: nil, &b)
      callable ||= b
      if stopped?
        callable && callable.call
        false
      else
        schedule_stop(callback: callable)
        true
      end
    end

    # Stop the dispatcher immediately by scheduling the stop action at the front of the
    # queue. This means that any other already scheduled items will be ignored.
    #
    # This action is idempotent; it returns true if the dispatcher is currently running
    # and will be stopped, false if it's already stopped.
    #
    # A callable can be provided either in the form of the `callable` option or a block,
    # which will be called after the dispatcher has stopped (also if dispatcher is already stopped).
    #
    # TODO                                         |------|--> find new name for this
    # If the `cleanup` option is true, all attached sources will have their `stop` method
    # called before shutdown.
    def stop!(callable: nil, cleanup: false, &b)
      callable ||= b
      if stopped?
        callable && callable.call
        false
      else
        unshift_stop(callback: callable, cleanup: cleanup)
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
          id, regex, handler = *vals
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
    #
    # Returns a unique ID which can be used to deregister the handler from the
    # dispatcher with `remove_handler`.
    def add_handler(type, callable=nil, &b)
      callable = callable(callable, b)
      regex = regex_for(type)
      sync do
        id = @handler_serial+=1
        handlers << [id, regex, callable]
        id
      end
    end
    alias subscribe add_handler
    alias on add_handler


    def remove_handler(id)
      index = handlers.index{|i,*| i == id }
      sync{ handlers.delete_at(index) }
    end
    alias unsubscribe remove_handler


    # Add a source to this dispatcher. Sources are objects that attach themselves
    # to the dispatcher during its lifecycle and listen for or send events. Examples
    # of sources are SignalSource, LogSource and LogSink, that use the dispatcher to
    # listen for and dispatch interrupt signals and log messages.
    #
    # `source` can be any object. It can also be a class, in which case its `new` method
    # will be called with the dispatcher as the argument. It is not required to add objects
    # that interact with the scheduler using this method, but doing so has some advantages:
    #
    # * If a second argument is provided, an accessor to the object will be available
    #   on the dispatcher with the name provided:
    #
    #     dispatcher.add(SignalSource, :signals)
    #     dispatcher.signals.on_int{ puts "Got INT"; dispatcher.stop }
    #
    # * Any object registered in this way will have a chance to clean up its state before the
    #   dispatcher shuts down, if it responds to `stop`:
    #     class PingPong
    #       def initialize(d)
    #         @dispatcher = d
    #         @dispatcher.on('ping'){ @dispatcher.signal('pong') }
    #       end
    #       def stop
    #         @dispatcher.
    #       end
    #     end
    def add(source, name=nil)
      source = source.new(self) if source.is_a?(Class)
      sync do
        sources << source
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

    def sources
      @sources
    end

    def callable(*cs)
      cs.each do |c|
        return c if c
      end
      raise ArgumentError, "No callable detected"
    end

    # Called from inside the loop to execute a callable. This method is extracted only to
    # avoid repetition; it's not to be used for other purposes.
    def run_callable(callable, args)
      if callable.is_a?(STOP)
        @state = STOPPED
        callable.call(*args)
        true #Loop should be stopped
      else
        callable.call(*args)
        false #Loop should continue
      end
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
      sleep 0.01 until running #Block current thread until scheduler thread is up and running
      @thread.abort_on_exception = true
      @thread
    end


    def join(*a)
      raise "Dispatcher not running, can't join" unless running?
      @thread.join(*a)
    end

    def wait(*a)
      stop
      join(*a)
    end


  end#class ThreadedDispatcher




end#module Enkidu
