http = require "socket.http"
logger = require "lapis.logging"

import from_json, encode_query_string from require "lapis.util"

-- HTTP interface to influxdb
class Influxdb
  @get_client: =>
    @client or= Influxdb require("lapis.config").get!.influxdb
    @client

  new: (config) =>
    assert config, "missing config for influxdb"
    host = config.host or "127.0.0.1"
    port = config.port or 8086
    @database = assert config.database, "missing database"

    if user = config.username
      host = "#{user}:#{config.password}@#{host}"

    @url = "http://#{host}:#{port}"

  write: (points) =>
    if type(points) == "table"
      points = table.concat points, "\n"

    url = "#{@url}/write?db=#{@database}"
    http.request url, points

  query: (q, ...) =>
    if 0 != select "#", ...
      args = {...}
      i = 0
      q = q\gsub "%?", ->
        i += 1
        "\"#{tostring args[i]}\""


    params = encode_query_string { db: @database, :q }
    logger.query q
    res, status = assert http.request "#{@url}/query", params

    res = from_json res

    if res.error
      error res.error

    results = res.results

    if results[1] and results[1].error
      error "#{results[1].error}\n#{q}"

    res, status

  get_databases: =>
    [d[1] for d in *@query("show databases").results[1].series[1].values]

  create_database: (force) =>
    for d in *@get_databases!
      if d == @database
        if force == true
          @query "drop database ?", @database
          break
        else
          return nil, "Database `#{@database}` already exists, aborting"

    @query "create database ?", @database
    true

{
  :Influxdb
  get_client: Influxdb\get_client
  query: (...) ->
    Influxdb\get_client!\query ...

  write: (...) ->
    Influxdb\get_client!\write ...
}
