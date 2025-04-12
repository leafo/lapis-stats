
-- This is a client to interface with the victoria metrics server over http

-- Query Syntax:
-- https://docs.victoriametrics.com/keyConcepts.html#metricsql

-- WARNING: http client is blocking in nginx, don't use this in nginx

http = require "socket.http"
ltn12 = require "ltn12"

import encode_query_string from require "lapis.util"

-- a VictoriaMetrics timestamp is unix time in ms
timestamp_to_date = (ts) ->
  date = require "date"
  ts = tonumber ts
  return nil, "invalid timestamp" unless ts
  date ts/1000

-- https://github.com/prometheus/docs/blob/main/content/docs/instrumenting/exposition_formats.md
-- value: is optional
encode_metric = (name, labels, value) ->
  out = {name}

  label_names = labels and [k for k in pairs(labels)]

  if labels and next label_names
    -- bubble host up
    table.sort label_names, (a, b) ->
      if a == "host"
        return true

      if b == "host"
        return false

      a < b

    for idx, ln in ipairs label_names
      if idx == 1
        table.insert out, "{"
      else
        table.insert out, ","

      label_value = labels[ln]\gsub([["]], [[\"]])\gsub([[\]], [[\\]])
      table.insert out, "#{ln}=\"#{label_value}\""

    table.insert out, "}"

  if value != nil
    table.insert out, " #{value}"

  table.concat out

class VictoriaMetrics
  @get_client: =>
    @client or= VictoriaMetrics require("lapis.config").get!.victoriametrics
    @client

  new: (config={}) =>
    assert config, "missing config for victoriametrics"
    host = config.host or "127.0.0.1"
    port = config.port or 8428

    if user = config.username
      assert config.password, "missing password for victoriametrics"
      host = "#{user}:#{config.password}@#{host}"

    @url = "http://#{host}:#{port}"

  -- https://docs.victoriametrics.com/keyConcepts.html#instant-query
  query: (query, time, step) =>
    res, status = @_request "api/v1/query", {
      method: "POST"
      body: {
        :query
        :time
        :step
      }
    }

    if status == 200
      res
    else
      nil, "Failed to get response: #{status}"

  -- Used for createing graphs
  -- https://docs.victoriametrics.com/keyConcepts.html#range-query
  query_range: (query, _start, _end, step) =>
    res, status = @_request "api/v1/query_range", {
      method: "POST"
      body: {
        :query
        start: _start
        end: _end
        :step
      }
    }


    if status == 200
      res
    else
      nil, "Failed to get response: #{status}"

  -- https://docs.victoriametrics.com/#how-to-export-data-in-json-line-format
  export: (match, _start, _end) =>
    if match == true -- return EVERYTHING
      match = '{__name__!=""}'

    assert type(match) == "string", "missing match query for export (pass true to export all)"

    res, status = @_request "api/v1/export", {
      method: "POST"
      body: {
        "match[]": match
        "start": _start
        "end": _end
      }
    }

    if status == 200
      res
    else
      nil, "Failed to get response: #{status}"

  -- write prometheus formatted metrics to victoria metrics
  -- my_metric{label="value"} 123
  write: (metrics) =>
    assert type(metrics) == "string", "missing metrics for victoriametrics"

    _, status = @_request "api/v1/import/prometheus", {
      method: "POST"
      body: metrics
      headers: {
        ["Content-Type"]: "application/octet-stream"
      }

    }

    status == 204

  -- import data into victoria metrics
  import: (data) =>
    assert type(data) == "string", "missing data for victoriametrics"

    res, status = @_request "api/v1/import", {
      method: "POST"
      body: data
      headers: {
        ["Content-Type"]: "application/json"
      }
    }

    if status == 200 or status == 204
      res
    else
      nil, "Failed to import data: #{status}"

  -- this will delete the *entire* series of data for a metric. Only do this if
  -- you really messed up. VM does not support partial deletes
  -- curl -v http://localhost:8428/api/v1/admin/tsdb/delete_series -d 'match[]=vm_http_request_errors_total'
  delete_series: (name, name_confirm=false) =>
    assert name == name_confirm, "Please pass in the name twice to confirm"

    @_request "api/v1/admin/tsdb/delete_series", {
      method: "POST"
      body: {
        "match[]": name
      }
    }

  _request: (path, opts={}) =>
    assert not _G.ngx, "Don't use this in nginx, it uses blocking lua socket"

    url = "#{@url}/#{path}"

    if opts.params
      url ..= "?" .. encode_query_string opts.params

    headers = { }

    body = switch type opts.body
      when "table"
        headers["Content-Type"] or= "application/x-www-form-urlencoded"
        encode_query_string opts.body
      when "string"
        opts.body

    if body
      headers["Content-Length"] = "#{#body}"

    method = opts.method or body and "POST" or "GET"

    sink = {}

    _, status, out_headers = http.request {
      :url
      :method
      sink: ltn12.sink.table(sink)
      source: body and ltn12.source.string(body) or nil
      :headers
    }

    table.concat(sink), status, out_headers

write = (str) -> VictoriaMetrics\get_client!\write str

{:VictoriaMetrics, :encode_metric, :write, :timestamp_to_date}

