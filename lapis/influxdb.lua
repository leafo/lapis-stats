local http = require("socket.http")
local logger = require("lapis.logging")
local from_json, encode_query_string
do
  local _obj_0 = require("lapis.util")
  from_json, encode_query_string = _obj_0.from_json, _obj_0.encode_query_string
end
local Influxdb
do
  local _class_0
  local _base_0 = {
    write = function(self, points)
      if type(points) == "table" then
        points = table.concat(points, "\n")
      end
      local url = tostring(self.url) .. "/write?db=" .. tostring(self.database)
      return http.request(url, points)
    end,
    query = function(self, q, ...)
      if 0 ~= select("#", ...) then
        local args = {
          ...
        }
        local i = 0
        q = q:gsub("%?", function()
          i = i + 1
          return "\"" .. tostring(tostring(args[i])) .. "\""
        end)
      end
      local params = encode_query_string({
        db = self.database,
        q = q
      })
      logger.query(q)
      local res, status = assert(http.request(tostring(self.url) .. "/query", params))
      res = from_json(res)
      if res.error then
        error(res.error)
      end
      local results = res.results
      if results[1] and results[1].error then
        error(tostring(results[1].error) .. "\n" .. tostring(q))
      end
      return res, status
    end,
    get_databases = function(self)
      local _accum_0 = { }
      local _len_0 = 1
      local _list_0 = self:query("show databases").results[1].series[1].values
      for _index_0 = 1, #_list_0 do
        local d = _list_0[_index_0]
        _accum_0[_len_0] = d[1]
        _len_0 = _len_0 + 1
      end
      return _accum_0
    end,
    create_database = function(self, force)
      local _list_0 = self:get_databases()
      for _index_0 = 1, #_list_0 do
        local d = _list_0[_index_0]
        if d == self.database then
          if force == true then
            self:query("drop database ?", self.database)
            break
          else
            return nil, "Database `" .. tostring(self.database) .. "` already exists, aborting"
          end
        end
      end
      self:query("create database ?", self.database)
      return true
    end
  }
  _base_0.__index = _base_0
  _class_0 = setmetatable({
    __init = function(self, config)
      assert(config, "missing config for influxdb")
      local host = config.host or "127.0.0.1"
      local port = config.port or 8086
      self.database = assert(config.database, "missing database")
      do
        local user = config.username
        if user then
          host = tostring(user) .. ":" .. tostring(config.password) .. "@" .. tostring(host)
        end
      end
      self.url = "http://" .. tostring(host) .. ":" .. tostring(port)
    end,
    __base = _base_0,
    __name = "Influxdb"
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
  self.get_client = function(self)
    self.client = self.client or Influxdb(require("lapis.config").get().influxdb)
    return self.client
  end
  Influxdb = _class_0
end
return {
  Influxdb = Influxdb,
  get_client = (function()
    local _base_0 = Influxdb
    local _fn_0 = _base_0.get_client
    return function(...)
      return _fn_0(_base_0, ...)
    end
  end)(),
  query = function(...)
    return Influxdb:get_client():query(...)
  end,
  write = function(...)
    return Influxdb:get_client():write(...)
  end
}
