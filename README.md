# lapis-stats

Statsd and Influxdb support for Lua, OpenResty &amp; Lapis

* [statsd](#statsd)
* [influxdb](#influxdb)

## statsd

The `lapis.statsd` module lets you send metrics to statsd with a UDP socket.
Inside of OpenResty the non-blocking co-socket API is used. Otherwise,
LuaSocket is used.

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


## influxdb

The `lapis.influxdb` module provides a way to configure and send data to
InfluxDB over the HTTP API.

> TODO: only LuaSocket is used right now

You must configure your InfluxDB server in your Lapis config:

```lua
-- config.lua

local config = require("lapis.config")

config("development", function()
  influxdb {
    -- host = "127.0.0.1", -- default
    -- port = 8086, -- default
    username = "influx",
    password = "my-password",
    database = "my-db",
  }
end)
```

You can then use the module to query data:

```lua
local influxdb = require("lapis.influxdb")

local res = influxdb.query([[
  select * from "counts.users" where time > now() - 1d group by time(1h)
]])
```

Or write data points:

```lua
local res = influxdb.write {
  "count.users value=4",
  "summary.ip count=32 tag=US"
}
```

### Reference

#### `get_client()`

Get the current instance of the InfluxDB client from the Lapis configuration.

#### `query(query, values...)`

Send a query to the current connection. The values are interpolated into the
query escaped where the character `?` appears.


```lua
local res = influxdb.query([[
  select * from "counts.users" where tag = ?
]], "hello world")
```

The response is returned as an array table of results.

#### `write(points)`

Write measurements to the database. `points` is an array table with all the
measurements to write as a string. It uses the [same text syntax documented in
the InfluxDB
manual](https://docs.influxdata.com/influxdb/v1.0/guides/writing_data/).

```lua
local res = influxdb.write {
  "count.users value=4",
}
```

## Writing an InfluxDB sink for Statsd

Using this library you can write a command line script to use as a sink to
handle your `statsd` flush to InfluxDB.

> Note: I recommend using [statsite](https://github.com/armon/statsite) over statsd

You might write something like this:

```lua
-- influxdb_sink.lua
local influxdb = require("lapis.influxdb").get_client()

local points = {}

for line in io.stdin:lines() do
  local name, val, time = line:match("^([^|]+)|([^|]+)|([^|]+)$")
  if name then
     table.insert(points, name .. " value=" .. val)
  end
end

if not next(points) then
  return
end

influxdb:write(points)
```
