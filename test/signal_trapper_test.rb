require 'test_shared'
require 'enkidu/signals'


class SignalTrapperTest < EnkiduTestCase

  include Enkidu


  test "normalize_signal" do
    assert_equal 'INT', SignalTrapper.normalize_signal('SIGINT')
    assert_equal 'TERM', SignalTrapper.normalize_signal(15)
    assert_equal 'USR1', SignalTrapper.normalize_signal('30')
    assert_equal 'KILL', SignalTrapper.normalize_signal('KILL')
    assert_raises(ArgumentError){ SignalTrapper.normalize_signal(1234) }
  end

  test "we" do
    r, w = IO.pipe
    child = spork do
      r.close
      st = SignalTrapper.new
      st.register('USR1', ->(s){ w.write 'USR1' })
      id = st.register('USR1', ->(s){ w.write 'kimono' })
      st.register('INT', ->(s){ w.write 'INT' })
      signal     #Let parent know we're ready to receive signals
      wait       #Wait for the parent to send the signals
      st.deregister(id)
      signal     #Tell parent (one) USR1 handler deregistered
      wait       #Wait for parent to send USR1
      st.wait    #Wait for the signal handling thread to empty the queue before exiting
    end
    w.close
    child.wait   #Wait for the child to be ready to receive signals
    Process.kill 'INT', child.pid
    Process.kill 'USR1', child.pid
    child.signal #Tell the child we've sent the signals
    child.wait   #Wait for child to deregister one of the USR1 handlers
    Process.kill 'USR1', child.pid #This should only trigger the first USR1 handler at this point
    child.signal #Tell child USR1 has been sent
    child.join
    assert_equal 'INTUSR1kimonoUSR1', r.read
  end


end
