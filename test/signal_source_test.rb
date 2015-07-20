require 'test_shared'
require 'enkidu/signals'
require 'enkidu/dispatcher'


class SignalSourceTest < EnkiduTestCase

  include Enkidu


  test "sdfwefwe" do
    r, w = IO.pipe
    child = spork do
      r.close
      d = ThreadedDispatcher.run
      s = SignalSource.new(d)
      s.register 'USR1'
      d.on('signal.USR1'){|sig| w.write "#{sig}," }
      s.on('INT'){ w.write 'humbaba,' }
      s.on_term{ w.write 'ishtar,' }
      id = s.on_term{ w.write 'enki,' }[0]
      signal#1
      wait#2
      s.off(id)
      signal#3
      wait#4
      d.wait
    end
    w.close
    child.wait#1
    Process.kill 'USR1', child.pid
    Process.kill 'TERM', child.pid
    Process.kill 'INT', child.pid
    child.signal#2
    child.wait#3
    Process.kill 'TERM', child.pid
    child.signal#4
    child.join
    #Split into array and sort because the order of the signals is not guaranteed
    assert_equal ['USR1', 'ishtar', 'enki', 'humbaba', 'ishtar'].sort, r.read.split(',').sort
  end


end
