
argparser = ->
  argparse = require "argparse"

  parser = argparse("stat_postgres", "metrics collection for postgres")
  parser\flag "--send", "Send metrics to VictoriaMetrics server instead of printing to stdout"

  parser\flag "--pgbouncer", "Include metrics from pgbouncer database"

  parser

run = (args, lapis_args) =>
  db = require "lapis.db"
  config = require("lapis.config").get!
  date = require "date"
  dbname = config.postgres.database

  import VictoriaMetrics, encode_metric from require "helpers.victoriametrics"

  import from_json, to_json from require "lapis.util"

  events = {}

  fields = {
    "tup_returned", "tup_fetched", "tup_updated", "tup_deleted", "tup_inserted"
    "xact_commit", "xact_rollback", "temp_files", "temp_bytes", "blks_read"
    "blks_hit", "conflicts", "blk_read_time", "blk_write_time"
  }

  stats = unpack db.query "
    select *,
      date_trunc('second', now() at time zone 'utc') as now,
      date_trunc('second', stats_reset at time zone 'utc') as stats_reset_trunc
    from pg_stat_database where datname = ?
  ", dbname


  database_size = ->
    unpack db.query [[
      select
        sum(pg_table_size(table_schema || '.' || table_name)) table_size,
        sum(pg_indexes_size(table_schema || '.' || table_name)) indexes_size,
        sum(pg_total_relation_size(table_schema || '.' || table_name)) total_size
      from information_schema.tables
    ]]

  do -- postgres status
    for field in *fields
      value = stats[field]
      continue unless value
      table.insert events, encode_metric "pg_stat_database_#{field}", {
        db: dbname
      }, value

    for key, bytes in pairs database_size!
      table.insert events, encode_metric "pg_#{key}_bytes", {
        db: dbname
      }, bytes


  if args.pgbouncer -- pgbouncer stats
    import Postgres from require "pgmoon"
    pgbouncer = Postgres {
      database: "pgbouncer"
      host: config.postgres.host
      port: config.postgres.port
      user: config.postgres.user
      password: config.postgres.password
    }

    success, err = pgbouncer\connect!
    if success
      for row in *pgbouncer\query "SHOW stats_totals"
        continue unless row.database == dbname
        for k,v in pairs row
          continue if k == "database"
          table.insert events, encode_metric "pgbouncer_#{k}", {
            db: dbname
          }, v
    else
      io.stderr\write "couldn't stat pgbouncer: #{err}\n"

  events = table.concat events, "\n"

  if args.send
    client = VictoriaMetrics\get_client!
    unless client\write events
      io.stderr\write "Failed to write events"
      os.exit 1
  else
    print events


{:argparser, run}
