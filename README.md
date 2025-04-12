# lapis-stats

Various helper modules for metrics and stats collection for Lua, OpenResty &amp; Lapis

* [statsd](#statsd)
* [victoriametrics](#victoriametrics)
* [influxdb](#influxdb)


## Lapis Actions

This library includes command-line actions that can be executed using the Lapis command-line tool. These actions are designed to collect metrics from various system components and format them for ingestion into monitoring systems like VictoriaMetrics.

They are typically run like this:

```bash
lapis _ <action_name> [options]
```

### `stat_system`

Collects system metrics like CPU and Disk usage and outputs them in Prometheus exposition format. It relies on standard Linux command-line tools (`mpstat`, `df`, `iostat`).

**Usage:**

```bash
# Print system metrics to standard output
lapis _ stat_system

# Send metrics directly to VictoriaMetrics (configured in Lapis config)
lapis _ stat_system --send

# Only collect CPU metrics, average over 5 seconds
lapis _ stat_system --skip-disk --interval 5

# Specify hostname label explicitly
lapis _ stat_system --hostname my-server-01
```

**Options:**

*   `--send`: Send metrics directly to the VictoriaMetrics server configured in the Lapis application configuration under the `victoriametrics` key instead of printing out the metrics.
*   `--skip-cpu`: Do not collect CPU metrics.
*   `--skip-disk`: Do not collect Disk metrics (usage, available, read/write stats).
*   `--hostname`: Manually specify the hostname to be used in the `host` label for all metrics. Defaults to the system's hostname.
*   `--interval <seconds>`: The interval (in seconds) over which to average CPU usage when running `mpstat`. Defaults to `2`.

**Dependencies:** Requires `mpstat` (often part of the `sysstat` package), `df`, and `iostat` to be installed and available in the system's `PATH`.

### `stat_postgres`

Collects metrics from a PostgreSQL database instance, including database statistics and optionally PgBouncer statistics. Outputs metrics in Prometheus exposition format.

**Usage:**

```bash
# Print PostgreSQL metrics for the configured database to standard output
lapis _ stat_postgres

# Include PgBouncer metrics
lapis _ stat_postgres --pgbouncer

# Send metrics directly to VictoriaMetrics
lapis _ stat_postgres --send --pgbouncer
```

**Options:**

*   `--send`: Send metrics directly to the VictoriaMetrics server configured in the Lapis application configuration under the `victoriametrics` key.
*   `--pgbouncer`: Connect to the `pgbouncer` database (using the same credentials as the main database connection configured in Lapis, but targeting the `pgbouncer` database name) and collect statistics using `SHOW stats_totals`.

**Dependencies:** Requires PostgreSQL connection details to be configured in the Lapis application configuration (e.g., under the `postgres` key). If `--pgbouncer` is used, the configured user must have permission to connect to the `pgbouncer` administrative database and run `SHOW` commands.


## statsd

The `lapis.statsd` module lets you send metrics to statsd compatible
aggregation server over UDP socket. This is suitable for high-throughput
metrics collection. Inside of OpenResty the non-blocking co-socket API is
used. Otherwise, LuaSocket is used.

> Note: I recommend using [statsite](https://github.com/statsite/statsite)

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



## victoriametrics

The `lapis.victoriametrics` module provides a client to interface with a
[VictoriaMetrics](https://victoriametrics.com/) server over its HTTP API.

You must configure your VictoriaMetrics server details in your Lapis config:

```lua
-- config.lua

local config = require("lapis.config")

config("development", {
  victoriametrics = {
    -- host = "127.0.0.1", -- default
    -- port = 8428, -- default
    -- username = "my_user", -- optional
    -- password = "my_password", -- required if username is set
  }
})
```

You can then get a client instance and interact with the API:

```lua
local vm = require("lapis.victoriametrics").get_client()

-- Execute an instant query
local res, err = vm:query('sum(rate(my_counter_total[5m]))')
if res then
  print(res.status) -- "success"
  -- process res.data
end

-- Execute a range query
local start_time = os.time() - 3600 -- 1 hour ago
local end_time = os.time()
local res, err = vm:query_range('http_requests_total{host="example.com"}', start_time, end_time, "1m")

-- Write data using Prometheus exposition format
local ok = vm:write([[
my_metric{label="value1"} 123
another_metric{host="serverA",region="us-east"} 45.67
]])

if ok then
  print("Write successful")
end
```

### Module Reference

#### `encode_metric(name, labels, value)`

Formats a single metric into the Prometheus exposition format string. This is a helper function used internally by the `write` method.

*   `name`: (String) The name of the metric.
*   `labels`: (Optional Table) A table of key-value pairs representing the metric's labels. Keys and values should be strings.
*   `value`: (Optional Number/String) The value of the metric. Can be omitted if the metric doesn't have a value (e.g., info metrics, though less common).

Returns a string formatted according to the [Prometheus Exposition Format](https://github.com/prometheus/docs/blob/main/content/docs/instrumenting/exposition_formats.md).

```lua
local victoriametrics = require("lapis.victoriametrics")

local metric_string = victoriametrics.encode_metric("http_requests_total", {
  method = "POST",
  path = "/api/users"
}, 1027)

print(metric_string)
-- Output: http_requests_total{method="POST",path="/api/users"} 1027

local metric_string_no_value = victoriametrics.encode_metric("build_info", {
  version = "1.2.3",
  revision = "abcdef"
})

print(metric_string_no_value)
-- Output: build_info{version="1.2.3",revision="abcdef"}
```

#### `get_client()`

Get the singleton instance of the VictoriaMetrics client configured via the Lapis
configuration.

```lua
local vm = require("lapis.victoriametrics").get_client()
```

#### `write(metrics)`

Helper function to write metrics to the singleton client returned by `get_client()`.

#### `VictoriaMetrics`

Creates a new VictoriaMetrics client instance with a specific configuration
table, bypassing the global Lapis configuration. The `config` table expects keys
like `host`, `port`, `username`, `password`.

```lua
local VictoriaMetrics = require("lapis.victoriametrics").VictoriaMetrics

-- Create a client connected to a specific server, ignoring global config
local client = VictoriaMetrics({
  host = "victoriametrics.internal.example.com",
  port = 8428,
  username = "importer",
  password = "supersecretpassword"
})

-- Use the custom client
local ok = client:write("my_custom_metric 123")

### Client Reference

#### `client:query(query, time, step)`

Executes an instant query at a single point in time.
See [VictoriaMetrics Instant Query API](https://docs.victoriametrics.com/keyConcepts.html#instant-query).

*   `query`: (String) The MetricSQL query to execute.
*   `time`: (Optional Number) Unix timestamp in seconds for the evaluation time. Defaults to now if omitted.
*   `step`: (Optional String/Number) Evaluation step resolution.

Returns a table containing the decoded JSON response on success (HTTP 200), or
`nil` and an error message string on failure.

#### `client:query_range(query, start, end, step)`

Executes a query over a range of time.
See [VictoriaMetrics Range Query API](https://docs.victoriametrics.com/keyConcepts.html#range-query).

*   `query`: (String) The MetricSQL query to execute.
*   `start`: (Number) Start Unix timestamp in seconds.
*   `end`: (Number) End Unix timestamp in seconds.
*   `step`: (Optional String/Number) Query resolution step width (e.g., "1m", 60).

Returns a table containing the decoded JSON response on success (HTTP 200), or
`nil` and an error message string on failure.

#### `client:export(match, start, end)`

Exports raw data samples in JSON line format.
See [VictoriaMetrics Export API](https://docs.victoriametrics.com/#how-to-export-data-in-json-line-format).

*   `match`: (String) A time series selector for filtering (e.g., `{__name__="my_metric",job="my_job"}`). Pass `true` to export *all* data (use with caution).
*   `start`: (Optional Number) Start Unix timestamp in seconds.
*   `end`: (Optional Number) End Unix timestamp in seconds.

Returns the raw response body (JSON lines) as a string on success (HTTP 200), or
`nil` and an error message string on failure.

#### `client:write(metrics)`

Writes time series data using the Prometheus exposition format.
See [Prometheus Exposition Format](https://github.com/prometheus/docs/blob/main/content/docs/instrumenting/exposition_formats.md) and [VictoriaMetrics Import API](https://docs.victoriametrics.com/#how-to-import-data-in-prometheus-exposition-format).

*   `metrics`: (String) A string containing one or more metrics in Prometheus text format, separated by newlines.

Example format:
```
metric_name{label1="value1",label2="value2"} 123.45
```
(Timestamp in ms can optionally be provided at the end).

Returns `true` on success (HTTP 204), or `false` otherwise.

#### `client:import(data)`

Imports data using the VictoriaMetrics native import format (JSON line format).
See [VictoriaMetrics Import API](https://docs.victoriametrics.com/#how-to-import-data-in-json-line-format).

*   `data`: (String) A string containing one or more data points in JSON line format, separated by newlines.

Example format:
```json
{"metric":{"__name__": "metric_name", "label1": "value1"}, "values": [10], "timestamps": [1640995200000]}
```

Returns the decoded JSON response table on success, or `nil` and an error
message string on failure. Status code checking might be required depending on
API behavior for partial success/failure.

#### `client:delete_series(name, name_confirm)`

**WARNING: This is a destructive operation and cannot be undone.**

Deletes *all* data points for the time series matching the provided selector(s).
Due to the potential impact, the selector must be provided twice for confirmation.
See [VictoriaMetrics Delete API](https://docs.victoriametrics.com/Single-server-VictoriaMetrics.html#how-to-delete-time-series).

*   `name`: (String) The time series selector to delete (e.g., `http_requests_total`, `{job="my_app"}`). This corresponds to the `match[]` parameter in the VM API.
*   `name_confirm`: (String) Must be identical to `name` to confirm the deletion.

Returns the raw response `body` and `status` code from the VictoriaMetrics API.

#### `client:_request(path, opts)`

Makes a manual HTTP request to the VictoriaMetrics server. Only use this function if none of the other client methods are suitable
*   `path`: (String) The API endpoint path (e.g., `api/v1/query`).
*   `opts`: (Optional Table) Request options:
    *   `method`: (String) HTTP method (e.g., "GET", "POST"). Defaults to "GET" or "POST" if `body` is present.
    *   `body`: (String or Table) The request body. If a table, it's URL-encoded (`application/x-www-form-urlencoded`).
    *   `params`: (Table) A table of key-value pairs to be URL-encoded as query parameters.
    *   `headers`: (Table) A table of additional HTTP headers.


## influxdb

> **Warning:** This module was written for InfluxDB 1.x and has not been updated. Unknown if it works with newer versions of InfluxDB.

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

> Note: I recommend using [statsite](https://github.com/statsite/statsite)

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

