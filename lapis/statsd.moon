config = require("lapis.config").get!

CONFIG_KEY = "statsd"

send_udp = ngx and (msg) ->
  return unless config[CONFIG_KEY]
  if config[CONFIG_KEY].debug
    print "statsd: #{msg}"
  sock = ngx.socket.udp!
  sock\setpeername config[CONFIG_KEY].host, config[CONFIG_KEY].port
  sock\send msg

unless send_udp
  socket = require "socket"
  send_udp = (msg) ->
    return unless config[CONFIG_KEY]
    udp = socket.udp!
    udp\sendto msg, config[CONFIG_KEY].host, config[CONFIG_KEY].port

timer = (key, ms) -> "#{key}:#{ms}|ms"
counter = (key, amount=1) -> "#{key}:#{amount}|c"
gauge = (key, amount) -> "#{key}:#{amount}|g"
value = (key, v) -> "#{key}:#{v}|kv"

measure = (key, fn) ->
  socket = require "socket"
  start = socket.gettime!
  res = { fn! }
  send_udp value key, 1000 * (socket.gettime! - start)
  unpack res

class Pipeline
  import insert from table

  timer: (...) => insert @, timer ...
  counter: (...) => insert @, counter ...
  gauge: (...) => insert @, gauge ...
  value: (...) => insert @, value ...

  flush: =>
    return unless @[1]
    send_udp table.concat @, "\n"

pipeline = -> Pipeline!
direct = (formatter) -> (...) -> send_udp formatter ...

{
  pipeline: Pipeline

  timer: direct timer
  counter: direct counter
  gauge: direct gauge
  value: direct value

  :measure
}
