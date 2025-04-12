local http = require("socket.http")
local ltn12 = require("ltn12")
local encode_query_string
encode_query_string = require("lapis.util").encode_query_string
local timestamp_to_date
timestamp_to_date = function(ts)
  local date = require("date")
  ts = tonumber(ts)
  if not (ts) then
    return nil, "invalid timestamp"
  end
  return date(ts / 1000)
end
local encode_metric
encode_metric = function(name, labels, value)
  local out = {
    name
  }
  local label_names = labels and (function()
    local _accum_0 = { }
    local _len_0 = 1
    for k in pairs(labels) do
      _accum_0[_len_0] = k
      _len_0 = _len_0 + 1
    end
    return _accum_0
  end)()
  if labels and next(label_names) then
    table.sort(label_names, function(a, b)
      if a == "host" then
        return true
      end
      if b == "host" then
        return false
      end
      return a < b
    end)
    for idx, ln in ipairs(label_names) do
      if idx == 1 then
        table.insert(out, "{")
      else
        table.insert(out, ",")
      end
      local label_value = labels[ln]:gsub([["]], [[\"]]):gsub([[\]], [[\\]])
      table.insert(out, tostring(ln) .. "=\"" .. tostring(label_value) .. "\"")
    end
    table.insert(out, "}")
  end
  if value ~= nil then
    table.insert(out, " " .. tostring(value))
  end
  return table.concat(out)
end
local VictoriaMetrics
do
  local _class_0
  local _base_0 = {
    query = function(self, query, time, step)
      local res, status = self:_request("api/v1/query", {
        method = "POST",
        body = {
          query = query,
          time = time,
          step = step
        }
      })
      if status == 200 then
        return res
      else
        return nil, "Failed to get response: " .. tostring(status)
      end
    end,
    query_range = function(self, query, _start, _end, step)
      local res, status = self:_request("api/v1/query_range", {
        method = "POST",
        body = {
          query = query,
          start = _start,
          ["end"] = _end,
          step = step
        }
      })
      if status == 200 then
        return res
      else
        return nil, "Failed to get response: " .. tostring(status)
      end
    end,
    export = function(self, match, _start, _end)
      if match == true then
        match = '{__name__!=""}'
      end
      assert(type(match) == "string", "missing match query for export (pass true to export all)")
      local res, status = self:_request("api/v1/export", {
        method = "POST",
        body = {
          ["match[]"] = match,
          ["start"] = _start,
          ["end"] = _end
        }
      })
      if status == 200 then
        return res
      else
        return nil, "Failed to get response: " .. tostring(status)
      end
    end,
    write = function(self, metrics)
      assert(type(metrics) == "string", "missing metrics for victoriametrics")
      local _, status = self:_request("api/v1/import/prometheus", {
        method = "POST",
        body = metrics,
        headers = {
          ["Content-Type"] = "application/octet-stream"
        }
      })
      return status == 204
    end,
    import = function(self, data)
      assert(type(data) == "string", "missing data for victoriametrics")
      local res, status = self:_request("api/v1/import", {
        method = "POST",
        body = data,
        headers = {
          ["Content-Type"] = "application/json"
        }
      })
      if status == 200 or status == 204 then
        return res
      else
        return nil, "Failed to import data: " .. tostring(status)
      end
    end,
    delete_series = function(self, name, name_confirm)
      if name_confirm == nil then
        name_confirm = false
      end
      assert(name == name_confirm, "Please pass in the name twice to confirm")
      return self:_request("api/v1/admin/tsdb/delete_series", {
        method = "POST",
        body = {
          ["match[]"] = name
        }
      })
    end,
    _request = function(self, path, opts)
      if opts == nil then
        opts = { }
      end
      assert(not _G.ngx, "Don't use this in nginx, it uses blocking lua socket")
      local url = tostring(self.url) .. "/" .. tostring(path)
      if opts.params then
        url = url .. ("?" .. encode_query_string(opts.params))
      end
      local headers = { }
      local body
      local _exp_0 = type(opts.body)
      if "table" == _exp_0 then
        local _update_0 = "Content-Type"
        headers[_update_0] = headers[_update_0] or "application/x-www-form-urlencoded"
        body = encode_query_string(opts.body)
      elseif "string" == _exp_0 then
        body = opts.body
      end
      if body then
        headers["Content-Length"] = tostring(#body)
      end
      local method = opts.method or body and "POST" or "GET"
      local sink = { }
      local _, status, out_headers = http.request({
        url = url,
        method = method,
        sink = ltn12.sink.table(sink),
        source = body and ltn12.source.string(body) or nil,
        headers = headers
      })
      return table.concat(sink), status, out_headers
    end
  }
  _base_0.__index = _base_0
  _class_0 = setmetatable({
    __init = function(self, config)
      if config == nil then
        config = { }
      end
      assert(config, "missing config for victoriametrics")
      local host = config.host or "127.0.0.1"
      local port = config.port or 8428
      do
        local user = config.username
        if user then
          assert(config.password, "missing password for victoriametrics")
          host = tostring(user) .. ":" .. tostring(config.password) .. "@" .. tostring(host)
        end
      end
      self.url = "http://" .. tostring(host) .. ":" .. tostring(port)
    end,
    __base = _base_0,
    __name = "VictoriaMetrics"
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
    self.client = self.client or VictoriaMetrics(require("lapis.config").get().victoriametrics)
    return self.client
  end
  VictoriaMetrics = _class_0
end
local write
write = function(str)
  return VictoriaMetrics:get_client():write(str)
end
return {
  VictoriaMetrics = VictoriaMetrics,
  encode_metric = encode_metric,
  write = write,
  timestamp_to_date = timestamp_to_date
}
