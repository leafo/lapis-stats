# lapis-stats

Statsd and Influxdb support for Lua, OpenResty &amp; Lapis


## statsd

The `statsd` module lets you send metrics to statsd with a UDP socket. Inside
of OpenResty the non-blocking co-socket API is used. Otherwise, LuaSocket is
used.

You must configure your statsd location in your Lapis config:

```lua
-- config.lua

local config = require("lapis.config")

config("development", function()
  statsd {
    host = "127.0.0.1",
    port = 8125,
    -- debug: true,
  }
end)
```

Include the module from `lapis.statsd`

```lua
local statsd = require("lapis.statsd")

app:get("/hello", function(self)
  statsd.counter("my_counter", 5)
  statsd.timer("my_counter", 100)
  statsd.value("hello", 9)
  statsd.guage("some_guage", -1)
end)
```

If you're sending many metrics at once then you can take advantage of the
`Pipeline` interface:

```lua
app:get("/hello", function(self)
  p = statsd.Pipeline()
  p:counter("my_counter", 5)
  p:timer("my_counter", 100)
  p:value("hello", 9)
  p:guage("some_guage", -1)
  p:flush()
end)
```

### Reference

* `timer(key, value)`
* `counter(key, value)`
* `guage(key, value)`
* `value(key, value)`

The `Pipeline` instance exposes all of the same functions, but as methods. (So
you should call them using `:`)

