require 'test_shared'
require 'enkidu/dispatcher'
require 'thread'
require 'timeout'

class DispatcherTest < EnkiduTestCase

  include Enkidu


  test "run_once" do
    value = nil
    d = Dispatcher.new
    d.run_once #Should do nothing
    assert_equal nil, value
    d.schedule{ value = 'humbaba' }
    d.run_once
    assert_equal 'humbaba', value
    d.schedule{ value = 'inanna' }     #runs first
    d.run_once{ value = 'ereshkigal' } #runs second, as callback to stop
    assert_equal 'ereshkigal', value
  end

  test "run_once with stop should leave explicitly scheduled STOP in queue" do
    value = nil
    d = Dispatcher.new
    d.schedule{ d.stop }            # The `d.stop` will add another STOP to the back of the queue, which at the point it gets executed
                                    # already contains [->{ value = 'humbaba' }, STOP], making it [->{ v = 'h' }, STOP, STOP]
                                    # The second STOP will then be left in the queue when the dispatcher stops.
    d.schedule{ value = 'humbaba' } #
    d.run_once                      # Queue at start: [->{ d.stop }, ->{ v = 'h' }, STOP]
    assert_equal 'humbaba', value
    Timeout.timeout(2){ d.run }     # Queue at second start: [STOP] - The STOP is the one added by the first scheduled callable ->{ d.stop }
  end


  test "repeated run/stop" do
    counter = 0
    d = Dispatcher.new
    d.schedule{ counter += 1 }
    d.run_once
    d.schedule{ counter += 1; d.stop{ counter += 1 } }
    d.run
    d.schedule{ counter += 1 }
    d.schedule{ d.stop }
    d.run
    assert_equal 4, counter
  end

  test "multiple calls to stop should leave additional STOPs in the queue" do
    d = Dispatcher.new
    d.schedule{ d.stop; d.stop; d.stop }
    #None of these timeouts should be reached, as the STOPs in the queue will make `run` return almost immediately
    Timeout.timeout(2){ d.run } # [STOP, STOP, STOP]
    Timeout.timeout(2){ d.run } # [STOP, STOP]
    Timeout.timeout(2){ d.run } # [STOP]
  end


  test "schedule_stop should add a STOP to the queue" do
    value = nil
    d = Dispatcher.new
    d.schedule{ value = 'humbaba' }
    d.schedule_stop
    Timeout.timeout(2){ d.run }
    assert_equal 'humbaba', value
  end

  test "stop! should add STOP to front of queue" do
    value = nil
    d = Dispatcher.new
    running = Waiter.new  #Signal that scheduler is running
    continue = Waiter.new #Signal that scheduler can continue after call to `stop!`
    d.schedule{ running.signal; continue.wait }
    d.schedule{ value = 'humbaba' } #This remains at the back of the queue with the STOP at the
                                    #front, meaning it should never run, and `value` should remain nil
    t = Thread.new{ d.run }
    running.wait    #Wait for scheduler to be running before continuing
    d.stop!         #Schedules STOP before ->{ v = 'h' }
    continue.signal #Scheduler thread can continue
    t.join          #Scheduler will stop and exit the thread
    assert_nil value#value never gets set
  end


  test "call to run should raise if already running" do
    w = Waiter.new
    d = Dispatcher.new
    t = Thread.new{ Thread.current.abort_on_exception=true; d.schedule{ w.signal }; d.run; }
    w.wait #wait for scheduler to be running
    assert_raises(Dispatcher::StateError){ d.run }
    d.stop
    t.join

    d = Dispatcher.new
    d.schedule{ d.run }
    assert_raises(Dispatcher::StateError){ d.run }

    d = Dispatcher.new
    d.schedule{ d.stop{ d.run } } #The dispatcher is not considered to be stopped until the stop callback has finished running
    assert_raises(Dispatcher::StateError){ d.run }
  end


  test "basic scheduling" do
    value = nil
    d = Dispatcher.new
    d.schedule{ value = 'humbaba' }
    d.run_once
    assert_equal 'humbaba', value
  end

  test "unshift scheduling should put callable in front of queue" do
    run_order = []
    d = Dispatcher.new
    d.schedule{ run_order << 'push' }
    d.unshift{ run_order << 'unshift' }
    d.run_once
    assert_equal ['unshift', 'push'], run_order
  end


  test "add should instantiate if source is a class" do
    value = nil
    Foo = Class.new do
      define_method :initialize do |d|
        value = d
      end
    end
    d = Dispatcher.new
    d.add Foo
    assert_equal d, value
  end

  test "stop should call stop on all registered sources to allow cleanup" do
    v = nil
    d = Dispatcher.new
    s = Object.new
    s.singleton_class.send(:define_method, :stop){ v = 'humbaba' }
    d.add s
    d.schedule{ d.stop }
    d.run
    assert_equal 'humbaba', v
  end

  test "stop! should not do source cleanup by default" do
    v = nil
    d = Dispatcher.new
    s = Object.new
    s.singleton_class.send(:define_method, :stop){ v = 'humbaba' }
    d.add s
    d.schedule{ d.stop! }
    d.run
    assert_nil v
  end

  test "stop! should do source cleanup when passed cleanup: true" do
    v = nil
    d = Dispatcher.new
    s = Object.new
    s.singleton_class.send(:define_method, :stop){ v = 'humbaba' }
    d.add s
    d.schedule{ d.stop!(cleanup: true) }
    d.run
    assert_equal 'humbaba', v
  end

  test "adding a source should call the run method on the source if the dispatcher is running" do
    v = nil
    d = Dispatcher.new
    w = Waiter.new
    t = Thread.new{ d.schedule{ w.signal }; d.run }
    s = Object.new
    s.singleton_class.send(:define_method, :run){ v = 'humbaba' }
    w.wait
    d.add s
    d.stop
    t.join
    assert_equal 'humbaba', v
  end

  test "adding a source should not call the run method if the dispatcher is not running" do
    v = nil
    d = Dispatcher.new
    s = Object.new
    s.singleton_class.send(:define_method, :run){ v = 'humbaba' }
    d.add s
    assert_nil v
  end

  test "all registered sources should have their run method called when the dispatcher starts running" do
    c = 0
    d = Dispatcher.new
    s1 = Object.new
    s1.singleton_class.send(:define_method, :run){ c += 1 }
    s2 = Object.new
    s2.singleton_class.send(:define_method, :run){ c += 1 }
    d.add s1
    d.add s2
    d.run_once
    assert_equal 2, c
  end


  test "string event subscription" do
    vs = []
    d = Dispatcher.new
    d.add_handler('humbaba'){|v| vs << v }
    d.add_handler('foo.bar'){|v| vs << v }
    d.signal 'humbaba', 'ereshkigal'
    d.signal 'foo.bar', 'enki'
    d.run_once
    assert_equal %w[ereshkigal enki].sort, vs.sort
  end

  test "array event subscription" do
    vs = []
    d = Dispatcher.new
    d.add_handler(['humbaba']){|v| vs << v }
    d.add_handler(['foo', 'bar']){|v| vs << v }
    d.signal 'humbaba', 'ereshkigal'
    d.signal 'foo.bar', 'enki'
    d.run_once
    assert_equal %w[ereshkigal enki].sort, vs.sort
  end

  test "regex event subscription" do
    vs = []
    d = Dispatcher.new
    d.add_handler(/humbaba/){|v| vs << v }
    d.signal 'humbaba', 'ereshkigal'
    d.signal 'xxhumbabaxx', 'enki'
    d.run_once
    assert_equal %w[ereshkigal enki].sort, vs.sort
  end

  test "event handler removal" do
    c = 0
    d = Dispatcher.new
    id = d.add_handler('humbaba'){ c += 1 } #Only this handler should be removed
    d.add_handler('humbaba'){ c += 1 }
    d.add_handler('nibiru'){ nothin; i should never run }
    d.signal 'humbaba'
    d.run_once
    assert_equal 2, c #2 handlers = 2 succs
    d.remove_handler(id)
    d.signal 'humbaba'
    d.run_once
    assert_equal 3, c #Would be 4 if both handlers still registered
  end


end
