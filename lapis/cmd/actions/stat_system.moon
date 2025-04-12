-- lapis stat_system | curl -v -X POST -s --data-binary @- http://127.0.0.1:8428/api/v1/import/prometheus

argparser = ->
  argparse = require "argparse"

  parser = argparse "lapis stat_system",
    "Generate and optionally send Prometheus metrics for CPU and Disk usage"

  parser\flag "--send", "Send metrics to Prometheus server"

  parser\flag "--skip-cpu", "Skip generating cpu metrics"
  parser\flag "--skip-disk", "Skip generating disk metrics"

  parser\option("--hostname", "Manually specify hostname")

  parser\option("--interval", "Number of seconds to average CPU usage over")\default("2")\convert tonumber


  parser

run = (args, lapis_args) =>
  events = {}

  import VictoriaMetrics, encode_metric from require "lapis.victoriametrics"

  hostname = args.hostname
  get_hostname = ->
    hostname or= io.popen("cat /etc/hostname")\read("*a")\gsub "%s+$", ""
    hostname

  unless args.skip_cpu
    f = io.popen "mpstat -o JSON #{args.interval} 1"
    import from_json from require "lapis.util"
    result = f\read "*a"

    -- metrics = require("helpers.metrics")
    METRIC_NAME = "cpu_usage_percent"
    FIELDS = { -- the cpu fields to ship to metrics
      "usr"
      "nice"
      "sys"
      "iowait"
      "irq"
      "soft"
      -- "steal" -- related to vm, not important
      -- "guest"
      -- "gnice"
      "idle"
    }

    local cpu_data
    pcall -> cpu_data = from_json result
    unless cpu_data
      io.stderr\write "Failed to parse output from mpstat"
      os.exit 1

    hosts = cpu_data.sysstat.hosts


    -- This should only return one host
    for host in *hosts
      hostname or= host.nodename
      cpu_loads = host.statistics[1]["cpu-load"]
      for row in *cpu_loads
        for field in *FIELDS
          value = row[field]
          continue unless value and value > 0

          table.insert events, encode_metric METRIC_NAME, {
            host: hostname
            cpu: row.cpu
            mode: field
          }, value

  unless args.skip_disk
    f = assert io.popen "df"
    payload = assert f\read "*a"
    lines = [line for line in payload\gmatch "[^\n]+"]
    table.remove lines, 1

    for line in *lines
      cols = [col for col in line\gmatch "[^%s]+"]
      {filesystem, _, used, available, _, mount} = cols
      continue if filesystem\match("tmpfs") or filesystem == "efivarfs"
      continue if mount\match "^/boot"

      used = tonumber used
      available = tonumber available

      percent = used / (used + available) * 100

      table.insert events, encode_metric "disk_used_bytes", {
        host: get_hostname!
        :mount
      }, used

      table.insert events, encode_metric "disk_available_bytes", {
        host: get_hostname!
        :mount
      }, available

      table.insert events, encode_metric "disk_usage_percent", {
        host: get_hostname!
        :mount
      }, percent


  -- generate read and write total with report with iostat
  unless args.skip_disk
    f = assert io.popen "iostat -o JSON"
    payload = assert f\read "*a"
    import from_json from require "lapis.util"
    local result
    unless pcall -> result = from_json payload
      io.stderr\write "Failed to parse output from iostat"
      os.exit 1

    import types from require "tableshape"
    parse_iostat = types.partial {
      sysstat: types.partial {
        hosts: types.partial {
          types.partial {
            statistics: types.partial {
              types.partial {
                disk: types.array_of types.scope types.partial({
                  kB_read: types.any\tag "read_kb"
                  kB_wrtn: types.any\tag "written_kb"
                  disk_device: types.any\tag "device"
                }), tag: "disks[]"
              }
            }
          }
        }
      }
    }

    {:disks} = assert parse_iostat result
    for disk in *disks
      for m in *{"read_kb", "written_kb"}
        continue unless disk[m]

        table.insert events, encode_metric "disk_total_#{m}", {
          host: get_hostname!
          device: disk.device
        }, disk[m]

  events = table.concat events, "\n"

  if args.send
    client = VictoriaMetrics\get_client!
    unless client\write events
      io.stderr\write "Failed to write events"
      os.exit 1
  else
    print events

{:argparser, run}
