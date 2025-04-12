local argparser
argparser = function()
  local argparse = require("argparse")
  local parser = argparse("lapis stat_system", "Generate and optionally send Prometheus metrics for CPU and Disk usage")
  parser:flag("--send", "Send metrics to Prometheus server")
  parser:flag("--skip-cpu", "Skip generating cpu metrics")
  parser:flag("--skip-disk", "Skip generating disk metrics")
  parser:option("--hostname", "Manually specify hostname")
  parser:option("--interval", "Number of seconds to average CPU usage over"):default("2"):convert(tonumber)
  return parser
end
local run
run = function(self, args, lapis_args)
  local events = { }
  local VictoriaMetrics, encode_metric
  do
    local _obj_0 = require("lapis.victoriametrics")
    VictoriaMetrics, encode_metric = _obj_0.VictoriaMetrics, _obj_0.encode_metric
  end
  require("moon").p(args)
  local hostname = args.hostname
  local get_hostname
  get_hostname = function()
    hostname = hostname or io.popen("cat /etc/hostname"):read("*a"):gsub("%s+$", "")
    return hostname
  end
  if not (args.skip_cpu) then
    local f = io.popen("mpstat -o JSON " .. tostring(args.interval) .. " 1")
    local from_json
    from_json = require("lapis.util").from_json
    local result = f:read("*a")
    local METRIC_NAME = "cpu_usage_percent"
    local FIELDS = {
      "usr",
      "nice",
      "sys",
      "iowait",
      "irq",
      "soft",
      "idle"
    }
    local cpu_data
    pcall(function()
      cpu_data = from_json(result)
    end)
    if not (cpu_data) then
      io.stderr:write("Failed to parse output from mpstat")
      os.exit(1)
    end
    local hosts = cpu_data.sysstat.hosts
    for _index_0 = 1, #hosts do
      local host = hosts[_index_0]
      hostname = hostname or host.nodename
      local cpu_loads = host.statistics[1]["cpu-load"]
      for _index_1 = 1, #cpu_loads do
        local row = cpu_loads[_index_1]
        for _index_2 = 1, #FIELDS do
          local _continue_0 = false
          repeat
            local field = FIELDS[_index_2]
            local value = row[field]
            if not (value and value > 0) then
              _continue_0 = true
              break
            end
            table.insert(events, encode_metric(METRIC_NAME, {
              host = hostname,
              cpu = row.cpu,
              mode = field
            }, value))
            _continue_0 = true
          until true
          if not _continue_0 then
            break
          end
        end
      end
    end
  end
  if not (args.skip_disk) then
    local f = assert(io.popen("df"))
    local payload = assert(f:read("*a"))
    local lines
    do
      local _accum_0 = { }
      local _len_0 = 1
      for line in payload:gmatch("[^\n]+") do
        _accum_0[_len_0] = line
        _len_0 = _len_0 + 1
      end
      lines = _accum_0
    end
    table.remove(lines, 1)
    for _index_0 = 1, #lines do
      local _continue_0 = false
      repeat
        local line = lines[_index_0]
        local cols
        do
          local _accum_0 = { }
          local _len_0 = 1
          for col in line:gmatch("[^%s]+") do
            _accum_0[_len_0] = col
            _len_0 = _len_0 + 1
          end
          cols = _accum_0
        end
        local filesystem, _, used, available, mount
        filesystem, _, used, available, _, mount = cols[1], cols[2], cols[3], cols[4], cols[5], cols[6]
        if filesystem:match("tmpfs") or filesystem == "efivarfs" then
          _continue_0 = true
          break
        end
        if mount:match("^/boot") then
          _continue_0 = true
          break
        end
        used = tonumber(used)
        available = tonumber(available)
        local percent = used / (used + available) * 100
        table.insert(events, encode_metric("disk_used_bytes", {
          host = get_hostname(),
          mount = mount
        }, used))
        table.insert(events, encode_metric("disk_available_bytes", {
          host = get_hostname(),
          mount = mount
        }, available))
        table.insert(events, encode_metric("disk_usage_percent", {
          host = get_hostname(),
          mount = mount
        }, percent))
        _continue_0 = true
      until true
      if not _continue_0 then
        break
      end
    end
  end
  if not (args.skip_disk) then
    local f = assert(io.popen("iostat -o JSON"))
    local payload = assert(f:read("*a"))
    local from_json
    from_json = require("lapis.util").from_json
    local result
    if not (pcall(function()
      result = from_json(payload)
    end)) then
      io.stderr:write("Failed to parse output from iostat")
      os.exit(1)
    end
    local types
    types = require("tableshape").types
    local parse_iostat = types.partial({
      sysstat = types.partial({
        hosts = types.partial({
          types.partial({
            statistics = types.partial({
              types.partial({
                disk = types.array_of(types.scope(types.partial({
                  kB_read = types.any:tag("read_kb"),
                  kB_wrtn = types.any:tag("written_kb"),
                  disk_device = types.any:tag("device")
                }), {
                  tag = "disks[]"
                }))
              })
            })
          })
        })
      })
    })
    local disks
    disks = assert(parse_iostat(result)).disks
    for _index_0 = 1, #disks do
      local disk = disks[_index_0]
      local _list_0 = {
        "read_kb",
        "written_kb"
      }
      for _index_1 = 1, #_list_0 do
        local _continue_0 = false
        repeat
          local m = _list_0[_index_1]
          if not (disk[m]) then
            _continue_0 = true
            break
          end
          table.insert(events, encode_metric("disk_total_" .. tostring(m), {
            host = get_hostname(),
            device = disk.device
          }, disk[m]))
          _continue_0 = true
        until true
        if not _continue_0 then
          break
        end
      end
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
