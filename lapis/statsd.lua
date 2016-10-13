local config = require("lapis.config").get()
local send_udp = ngx and function(msg)
  if not (config.statsd) then
    return 
  end
  if config.statsd.debug then
    print("statsd: " .. tostring(msg))
  end
  local sock = ngx.socket.udp()
  sock:setpeername(config.statsd.host, config.statsd.port)
  return sock:send(msg)
end
if not (send_udp) then
  local socket = require("socket")
  send_udp = function(msg)
    if not (config.statsd) then
      return 
    end
    local udp = socket.udp()
    return udp:sendto(msg, config.statsd.host, config.statsd.port)
  end
end
local timer
timer = function(key, ms)
  return tostring(key) .. ":" .. tostring(ms) .. "|ms"
end
local counter
counter = function(key, amount)
  if amount == nil then
    amount = 1
  end
  return tostring(key) .. ":" .. tostring(amount) .. "|c"
end
local gauge
gauge = function(key, amount)
  return tostring(key) .. ":" .. tostring(amount) .. "|g"
end
local value
value = function(key, v)
  return tostring(key) .. ":" .. tostring(v) .. "|kv"
end
local measure
measure = function(key, fn)
  local socket = require("socket")
  local start = socket.gettime()
  local res = {
    fn()
  }
  send_udp(value(key, 1000 * (socket.gettime() - start)))
  return unpack(res)
end
local Pipeline
do
  local _class_0
  local insert
  local _base_0 = {
    timer = function(self, ...)
      return insert(self, timer(...))
    end,
    counter = function(self, ...)
      return insert(self, counter(...))
    end,
    gauge = function(self, ...)
      return insert(self, gauge(...))
    end,
    value = function(self, ...)
      return insert(self, value(...))
    end,
    flush = function(self)
      if not (self[1]) then
        return 
      end
      return send_udp(table.concat(self, "\n"))
    end
  }
  _base_0.__index = _base_0
  _class_0 = setmetatable({
    __init = function() end,
    __base = _base_0,
    __name = "Pipeline"
  }, {
    __index = _base_0,
    __call = function(cls, ...)
      local _self_0 = setmetatable({}, _base_0)
      cls.__init(_self_0, ...)
      return _self_0
    end
  })
  _base_0.__class = _class_0
  local self = _class_0
  insert = table.insert
  Pipeline = _class_0
end
local pipeline
pipeline = function()
  return Pipeline()
end
local direct
direct = function(formatter)
  return function(...)
    return send_udp(formatter(...))
  end
end
return {
  pipeline = Pipeline,
  timer = direct(timer),
  counter = direct(counter),
  gauge = direct(gauge),
  value = direct(value),
  measure = measure
}
