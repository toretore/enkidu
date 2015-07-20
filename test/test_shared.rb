require 'minitest/autorun'

Thread.abort_on_exception = true

class EnkiduTestCase < MiniTest::Test

  def setup
    @setups && @setups.each do |setup|
      setup.call
    end
  end

  class << self


    def setup(&b)
      @setups ||= []
      @setups << b
    end


    def test(name, &b)
      define_method "test_#{name}", &b
    end


  end#class << self


  def spork(&b)
    Forker.new(&b)
  end



  # Create a child process that can wait for and send signals to parent.
  # This is done using process signalling (Process.kill) and sleep-waiting.
  # `wait` and `signal` can take the name of the signal to use, 'USR2' by default.
  #
  # Probably has lots of possible edge cases.
  # TODO Like the fact that the order in which signals are received is not guaranteed,
  #      to be the same as they're sent, so using this to signal that signals have been
  #      sent may result in the USR2 getting handled before the others, making it quite useless
  #
  #   child = Forker.new do #instance_eval'd in `child`
  #     wait #for signal from parent
  #     sleep 1
  #     signal #parent
  #   end
  #   sleep 1
  #   child.signal
  #   child.wait
  class Forker

    attr_reader :pid

    def initialize(&b)
      @ppid = $$
      @pid = Process.fork do
        instance_eval(&b)
      end
    end

    def wait(sig='USR2')
      done = false
      trap(sig){ done = true }
      sleep 0.05 until done
      trap(sig){} #reset
    end

    def signal(sig='USR2')
      pid = ($$ == @ppid ? @pid : @ppid)
      Process.kill sig, pid
    end

    def join
      raise "Can only be called from parent process" unless $$ == @ppid
      Process.wait @pid
    end

  end




  class Waiter
    def initialize
      @m, @cv = Mutex.new, ConditionVariable.new
      @signalled = false
    end
    def wait
      @m.synchronize{ @cv.wait(@m) until @signalled; @signalled = false }
    end
    def signal
      @m.synchronize{ @signalled = true; @cv.signal }
    end
  end





end
