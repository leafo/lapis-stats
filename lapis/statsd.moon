config = require("lapis.config").get!

send_udp = ngx and (msg) ->
  return unless config.statsd
  if config.statsd.debug
    print "statsd: #{msg}"
  sock = ngx.socket.udp!
  sock\setpeername config.statsd.host, config.statsd.port
  sock\send msg

unless send_udp
  socket = require "socket"
  send_udp = (msg) ->
    return unless config.statsd
    udp = socket.udp!
    udp\sendto msg, config.statsd.host, config.statsd.port


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
