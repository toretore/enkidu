# Enkidu - a process sidekick
#
# Enkidu is a little messaging tool that can be embedded inside your process
# to facilitate communication with the outside (and inside) world. Examples
# include logging, metrics and status introspection.
#
# It is a very simple event loop that dispatches messages to and from various
# listeners. For example, your process can have a LogSource to which all
# log messages are sent. Listeners to these log messages can then write the
# messages to file, emit them on the network, etc. Similarly, you can have a
# ZMQSource which listens for messages from the outside world and emits them
# internally. These messages can then be responded to; for example, you could
# ask a process about its status from the outside and it would be
module Enkidu
end#module Enkidu

require 'enkidu/dispatcher'
require 'enkidu/signals'
require 'enkidu/logging'
