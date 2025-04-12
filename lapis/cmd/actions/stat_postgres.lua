local argparser
argparser = function()
  local argparse = require("argparse")
  local parser = argparse("stat_postgres", "metrics collection for postgres")
  parser:flag("--send", "Send metrics to VictoriaMetrics server instead of printing to stdout")
  parser:flag("--pgbouncer", "Include metrics from pgbouncer database")
  return parser
end
local run
run = function(self, args, lapis_args)
  local db = require("lapis.db")
  local config = require("lapis.config").get()
  local date = require("date")
  local dbname = config.postgres.database
  local VictoriaMetrics, encode_metric
  do
    local _obj_0 = require("helpers.victoriametrics")
    VictoriaMetrics, encode_metric = _obj_0.VictoriaMetrics, _obj_0.encode_metric
  end
  local from_json, to_json
  do
    local _obj_0 = require("lapis.util")
    from_json, to_json = _obj_0.from_json, _obj_0.to_json
  end
  local events = { }
  local fields = {
    "tup_returned",
    "tup_fetched",
    "tup_updated",
    "tup_deleted",
    "tup_inserted",
    "xact_commit",
    "xact_rollback",
    "temp_files",
    "temp_bytes",
    "blks_read",
    "blks_hit",
    "conflicts",
    "blk_read_time",
    "blk_write_time"
  }
  local stats = unpack(db.query("\n    select *,\n      date_trunc('second', now() at time zone 'utc') as now,\n      date_trunc('second', stats_reset at time zone 'utc') as stats_reset_trunc\n    from pg_stat_database where datname = ?\n  ", dbname))
  local database_size
  database_size = function()
    return unpack(db.query([[      select
        sum(pg_table_size(table_schema || '.' || table_name)) table_size,
        sum(pg_indexes_size(table_schema || '.' || table_name)) indexes_size,
        sum(pg_total_relation_size(table_schema || '.' || table_name)) total_size
      from information_schema.tables
    ]]))
  end
  do
    for _index_0 = 1, #fields do
      local _continue_0 = false
      repeat
        local field = fields[_index_0]
        local value = stats[field]
        if not (value) then
          _continue_0 = true
          break
        end
        table.insert(events, encode_metric("pg_stat_database_" .. tostring(field), {
          db = dbname
        }, value))
        _continue_0 = true
      until true
      if not _continue_0 then
        break
      end
    end
    for key, bytes in pairs(database_size()) do
      table.insert(events, encode_metric("pg_" .. tostring(key) .. "_bytes", {
        db = dbname
      }, bytes))
    end
  end
  if args.pgbouncer then
    local Postgres
    Postgres = require("pgmoon").Postgres
    local pgbouncer = Postgres({
      database = "pgbouncer",
      host = config.postgres.host,
      port = config.postgres.port,
      user = config.postgres.user,
      password = config.postgres.password
    })
    local success, err = pgbouncer:connect()
    if success then
      local _list_0 = pgbouncer:query("SHOW stats_totals")
      for _index_0 = 1, #_list_0 do
        local _continue_0 = false
        repeat
          local row = _list_0[_index_0]
          if not (row.database == dbname) then
            _continue_0 = true
            break
          end
          for k, v in pairs(row) do
            local _continue_1 = false
            repeat
              if k == "database" then
                _continue_1 = true
                break
              end
              table.insert(events, encode_metric("pgbouncer_" .. tostring(k), {
                db = dbname
              }, v))
              _continue_1 = true
            until true
            if not _continue_1 then
              break
            end
          end
          _continue_0 = true
        until true
        if not _continue_0 then
          break
        end
      end
    else
      io.stderr:write("couldn't stat pgbouncer: " .. tostring(err) .. "\n")
    end
  end
  events = table.concat(events, "\n")
  if args.send then
    local client = VictoriaMetrics:get_client()
    if not (client:write(events)) then
      io.stderr:write("Failed to write events")
      return os.exit(1)
    end
  else
    return print(events)
  end
end
return {
  argparser = argparser,
  run
}
