require 'thread'

module Enkidu




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

    SIGNALS = Signal.list


    def initialize(dispatcher)
      @dispatcher = dispatcher
      @q = Queue.new
      run
    end

    def run
      Thread.new do
        loop do
          sig = @q.pop
          dispatcher.signal("signal.#{sig}", sig)
        end
      end
    end

    def on(*signals, callable:nil, &b)
      signals = signals.map do |signal|
        Integer === signal ? Signal.signame(signal) : signal
      end
      signals.each do |signal|
        dispatcher.on("signal.#{signal}", callable || b)
      end
      register *signals
    end
    alias trap on

    def register(*signals)
      signals.each do |signal|
        Signal.trap(signal){ @q.push signal } #TODO not reentrant
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


  end#class SignalSource




end#module Enkidu
