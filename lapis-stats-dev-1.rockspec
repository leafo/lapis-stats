package = "lapis-stats"
version = "dev-1"

source = {
  url = "git://github.com/leafo/lapis-stats.git",
}

description = {
  summary = "Statsd and Influxdb support for Lua, OpenResty & Lapis",
  homepage = "https://github.com/leafo/lapis-stats",
  license = "MIT"
}

dependencies = {
  "lua >= 5.1",
  "lapis",
}

build = {
  type = "builtin",
  modules = {
    ["lapis.cmd.actions.stat_postgres"] = "lapis/cmd/actions/stat_postgres.lua",
    ["lapis.cmd.actions.stat_system"] = "lapis/cmd/actions/stat_system.lua",
    ["lapis.influxdb"] = "lapis/influxdb.lua",
    ["lapis.statsd"] = "lapis/statsd.lua",
    ["lapis.victoriametrics"] = "lapis/victoriametrics.lua",
  }
}

