module Enkidu


  # SignalTrapper is a generic callback-based signal handling utility. It queues
  # all signals onto a background thread and all callbacks are run, synchronously
  # and serially, on this thread. This means signal handlers will be reentrant;
  # any callbacks registered are guaranteed to finish before any other callback
  # triggered by a signal starts running.
  #
  # Only one SignalTrapper should exist per process, as having multiple risks
  # one overriding the other's signal handlers.
  #
  #   st = SignalTrapper.new
  #   handler = -> s do
  #     puts "Received #{s}, shutting down..."
  #     app.stop #Do cleanup and shutdown
  #     st.stop  #Tell ST to stop
  #   end
  #   st.register('INT', handler)
  #   st.register('TERM', handler)
  #   usr1 = st.register('USR1', ->(s){ puts app.stats })
  #   st.register('USR2', ->(s){ st.deregister(usr1) })
  #
  #   st.join
  class SignalTrapper


    class Subscription
      attr_reader :signal, :id
      def initialize(s, i)
        @signal, @id = s, i
      end
      def ==(other)
        if other.is_a?(self.class)
          id == other.id
        else
          id == other
        end
      end
    end

    SIGNALS = Signal.list


    def initialize
      @q = []
      @r, @w = IO.pipe
      @trapped_signals = []
      @callbacks = Hash.new{|h,k| h[k] = [] }
      @callback_serial = -1
      @thread = Thread.new do
        loop do
          IO.select [@r]
          sig = @q.shift
          break if sig == :stop
          @r.read 1
          @callbacks[sig].each do |id, callable|
            callable.call(sig)
          end
        end
      end
    end


    # Register a callable for a specific signal. The callback will be scheduled
    # on the handler thread when the signal is received.
    #
    # Returns an ID which can be used to `deregister` the callback
    def register(sig, callable)
      sig = self.class.normalize_signal(sig)
      trap sig
      id = Subscription.new(sig, @callback_serial += 1)
      @callbacks[sig] << [id, callable]
      id
    end

    # Deregister a callback using the ID returned by `register`
    def deregister(id)
      @callbacks[id.signal].delete_if{|i, _c| i == id }
    end


    # Tell signal handling thread to stop. It will execute any already scheduled
    # handlers and then exit. No more handlers will be executed after that.
    def stop
      @q << :stop
      @w.write '.'
    end

    # Join the callback execution thread. This will block until the SignalTrapper
    # is told to `stop`.
    def join(*a, &b)
      @thread.join(*a, &b)
    end

    # `stop` and `join`
    def wait(*a, &b)
      stop
      join(*a, &b)
    end


    # Normalize signal name
    #
    #   2      -> INT
    #   SIGINT -> INT
    #   INT    -> INT
    #   123    -> ArgumentError
    def self.normalize_signal(sig)
      if sig.is_a?(Integer) || sig =~ /^\d+$/
        SIGNALS.key(sig.to_i) || raise(ArgumentError, "Unrecognized signal #{sig}")
      elsif sig =~ /^SIG(.+)$/
        $1
      else
        sig
      end
    end


  private

    def trap(sig)
      unless @trapped_signals.include?(sig)
        Signal.trap sig do
          @q << sig
          @w.write '.'
        end
      end
    end


  end#class SignalTrapper





  # A SignalSource will trap signals and put handlers on a Dispatcher's queue instead
  # of handling the signal immediately.
  #
  #   d = ThreadedDispatcher.new
  #
  #   s = SignalSource.new(d)
  #   s.on 'INT', 'TERM' do |sig|
  #     puts "Received #{sig}, cleaning up and shutting down"
  #     d.stop
  #   end
  #
  #   d.join
  class SignalSource

    SIGNALS = SignalTrapper::SIGNALS


    def initialize(dispatcher)
      @dispatcher = dispatcher
      @trapper = SignalTrapper.new
      @subscriptions = []
    end

    def run
    end

    def stop
    end

    def on(*signals, callable:nil, &b)
      subscriptions = signals.map do |signal|
        dispatcher.on("signal.#{signal}", callable || b)
      end
      register *signals
      subscriptions
    end
    alias trap on

    def off(*ids)
      ids.each do |id|
        dispatcher.unsubscribe(id)
      end
    end

    def register(*signals)
      signals.each do |signal|
        signal = SignalTrapper.normalize_signal(signal)
        unless @subscriptions.any?{|s| s.signal == signal }
          @subscriptions << trapper.register(
            signal,
            ->(s){ dispatcher.signal("signal.#{signal}", s) }
          )
        end
      end
    end


    SIGNALS.each do |name, number|
      define_method "on_#{name.downcase}" do |callable: nil, &b|
        on(name, callable:callable, &b)
      end
    end

  private

    def dispatcher
      @dispatcher
    end

    def trapper
      @trapper
    end


  end#class SignalSource




end#module Enkidu
