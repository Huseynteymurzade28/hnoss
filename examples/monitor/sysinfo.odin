package main

// Everything the monitor shows, read straight from /proc and /sys.
// References: proc(5) (https://man7.org/linux/man-pages/man5/proc.5.html),
// Documentation/hwmon/sysfs-interface.rst for temperatures.

import "core:mem"
import "core:mem/virtual"
import "core:os"
import "core:slice"
import "core:strconv"
import "core:strings"
import "core:time"

HISTORY :: 1024 // samples kept per graph (more than any terminal is wide)

Cpu_Times :: struct {
	busy, total: u64, // jiffies
}

Proc :: struct {
	pid:     int,
	name:    string, // in System.proc_arena
	user:    string, // in System.users
	state:   u8,
	threads: int,
	cpu:     f64, // percent of one core (can exceed 100 for multithreaded)
	rss_kb:  u64,
}

System :: struct {
	host, kernel, cpu_model: string,
	ncores:                  int,

	prev_cpu:   Cpu_Times,
	prev_cores: [dynamic]Cpu_Times,
	cpu:        f64,          // total, percent
	cores:      [dynamic]f64, // per core, percent
	cpu_hist:   [dynamic]f64,

	mem_total, mem_avail, mem_cached, swap_total, swap_free: u64, // kB
	mem_hist: [dynamic]f64,

	have_net:         bool,
	prev_rx, prev_tx: u64,
	prev_net:         time.Tick,
	rx_rate, tx_rate: f64, // bytes per second
	rx_hist, tx_hist: [dynamic]f64,

	load:         [3]f64,
	running:      int,
	uptime:       f64, // seconds
	temp_path:    string,
	temp:         f64, // °C, < 0 when unknown
	temp_hist:    [dynamic]f64,
	battery_dir:  string,
	battery:      int, // percent, < 0 when there is no battery
	charging:     bool,

	procs:           [dynamic]Proc,
	threads:         int,
	proc_arena:      virtual.Arena,
	prev_ticks:      map[int]u64,
	prev_proc_total: u64,
	users:           map[u32]string,
}

system_init :: proc(s: ^System) {
	_ = virtual.arena_init_growing(&s.proc_arena)
	s.host = strings.clone(strings.trim_space(read("/proc/sys/kernel/hostname")))
	s.kernel = strings.clone(strings.trim_space(read("/proc/sys/kernel/osrelease")))
	s.cpu_model = strings.clone(cpu_model())
	s.temp_path = strings.clone(find_temp_sensor())
	s.battery_dir = strings.clone(find_battery())
	s.temp = -1
	s.battery = -1
	load_users(s)
	sample_system(s)
	sample_procs(s)
}

system_destroy :: proc(s: ^System) {
	delete(s.host); delete(s.kernel); delete(s.cpu_model)
	delete(s.temp_path); delete(s.battery_dir)
	delete(s.prev_cores); delete(s.cores); delete(s.cpu_hist)
	delete(s.mem_hist); delete(s.rx_hist); delete(s.tx_hist); delete(s.temp_hist)
	delete(s.procs)
	delete(s.prev_ticks)
	for _, name in s.users { delete(name) }
	delete(s.users)
	virtual.arena_destroy(&s.proc_arena)
}

// CPU, memory, network, load, sensors. Cheap: call it a few times a second.
sample_system :: proc(s: ^System) {
	// /proc/stat: "cpu  user nice system idle iowait irq softirq steal ..."
	core := 0
	for line in strings.split_lines(read("/proc/stat"), context.temp_allocator) {
		if !strings.has_prefix(line, "cpu") { continue }
		t := parse_cpu_line(line)
		if strings.has_prefix(line, "cpu ") {
			s.cpu = usage(s.prev_cpu, t)
			s.prev_cpu = t
			continue
		}
		if core >= len(s.cores) {
			append(&s.cores, 0)
			append(&s.prev_cores, t)
		}
		s.cores[core] = usage(s.prev_cores[core], t)
		s.prev_cores[core] = t
		core += 1
	}
	s.ncores = max(len(s.cores), 1)
	push(&s.cpu_hist, s.cpu)

	for line in strings.split_lines(read("/proc/meminfo"), context.temp_allocator) {
		key, _, rest := strings.partition(line, ":")
		v := parse_u64(strings.trim_space(strings.trim_suffix(strings.trim_space(rest), "kB")))
		switch key {
		case "MemTotal":     s.mem_total = v
		case "MemAvailable": s.mem_avail = v
		case "Cached":       s.mem_cached = v
		case "SwapTotal":    s.swap_total = v
		case "SwapFree":     s.swap_free = v
		}
	}
	push(&s.mem_hist, 100 * f64(s.mem_total - s.mem_avail) / max(f64(s.mem_total), 1))

	// /proc/net/dev: "  eth0: rx_bytes rx_packets ... (8 rx fields) tx_bytes ..."
	rx, tx: u64
	for line, i in strings.split_lines(read("/proc/net/dev"), context.temp_allocator) {
		if i < 2 { continue }
		name, _, rest := strings.partition(line, ":")
		if strings.trim_space(name) == "lo" || rest == "" { continue }
		f := strings.fields(rest, context.temp_allocator)
		if len(f) >= 9 {
			rx += parse_u64(f[0])
			tx += parse_u64(f[8])
		}
	}
	now := time.tick_now()
	if s.have_net {
		dt := time.duration_seconds(time.tick_diff(s.prev_net, now))
		if dt > 0 {
			s.rx_rate = f64(rx - min(rx, s.prev_rx)) / dt
			s.tx_rate = f64(tx - min(tx, s.prev_tx)) / dt
		}
	}
	s.prev_rx, s.prev_tx, s.prev_net, s.have_net = rx, tx, now, true
	push(&s.rx_hist, s.rx_rate)
	push(&s.tx_hist, s.tx_rate)

	// "0.52 0.58 0.59 2/1234 5678"
	lf := strings.fields(read("/proc/loadavg"), context.temp_allocator)
	if len(lf) >= 4 {
		for i in 0 ..< 3 { s.load[i], _ = strconv.parse_f64(lf[i]) }
		running, _, _ := strings.partition(lf[3], "/")
		s.running = int(parse_u64(running))
	}
	up, _, _ := strings.partition(read("/proc/uptime"), " ")
	s.uptime, _ = strconv.parse_f64(up)

	if s.temp_path != "" {
		s.temp = f64(parse_u64(strings.trim_space(read(s.temp_path)))) / 1000
		push(&s.temp_hist, s.temp)
	}
	if s.battery_dir != "" {
		s.battery = int(parse_u64(strings.trim_space(read(join(s.battery_dir, "capacity")))))
		s.charging = strings.trim_space(read(join(s.battery_dir, "status"))) == "Charging"
	}
}

// Walks /proc/<pid>/ for every process. CPU% is measured since the last call.
sample_procs :: proc(s: ^System) {
	virtual.arena_free_all(&s.proc_arena)
	names := virtual.arena_allocator(&s.proc_arena)
	clear(&s.procs)
	s.threads = 0

	total := s.prev_cpu.total
	dtotal := f64(total - min(total, s.prev_proc_total))
	s.prev_proc_total = total

	ticks := make(map[int]u64, len(s.prev_ticks) + 64)
	entries, _ := os.read_all_directory_by_path("/proc", context.temp_allocator)
	for e in entries {
		pid, ok := strconv.parse_int(e.name)
		if !ok { continue }
		p, t, good := read_proc(s, pid, e.name, names)
		if !good { continue }
		if prev, seen := s.prev_ticks[pid]; seen && dtotal > 0 {
			p.cpu = f64(t - min(t, prev)) / dtotal * f64(s.ncores) * 100
		}
		ticks[pid] = t
		s.threads += p.threads
		append(&s.procs, p)
	}
	delete(s.prev_ticks)
	s.prev_ticks = ticks
}

@(private = "file")
read_proc :: proc(s: ^System, pid: int, dir: string, names: mem.Allocator) -> (p: Proc, ticks: u64, ok: bool) {
	stat := read(join_all("/proc/", dir, "/stat"))
	// "pid (comm) state ppid ..." where comm may itself contain ") ".
	open := strings.index_byte(stat, '(')
	close := strings.last_index_byte(stat, ')')
	if open < 0 || close < open || close + 2 > len(stat) {
		return
	}
	f := strings.fields(stat[close + 2:], context.temp_allocator)
	if len(f) < 22 {
		return
	}
	// Fields after comm, 0-based here = proc(5) number - 3:
	// state(3) utime(14) stime(15) num_threads(20).
	p.pid = pid
	p.name = strings.clone(stat[open + 1:close], names)
	p.state = f[0][0]
	ticks = parse_u64(f[11]) + parse_u64(f[12])
	p.threads = int(parse_u64(f[17]))

	for line in strings.split_lines(read(join_all("/proc/", dir, "/status")), context.temp_allocator) {
		switch {
		case strings.has_prefix(line, "Uid:"):
			uf := strings.fields(line[4:], context.temp_allocator)
			if len(uf) > 0 {
				p.user = s.users[u32(parse_u64(uf[0]))] or_else "?"
			}
		case strings.has_prefix(line, "VmRSS:"):
			p.rss_kb = parse_u64(strings.trim_space(strings.trim_suffix(strings.trim_space(line[6:]), "kB")))
		}
	}
	return p, ticks, true
}

Sort_Key :: enum u8 { Cpu, Mem, Pid, Name }

sort_procs :: proc(procs: []Proc, key: Sort_Key, reverse: bool) {
	less :: proc(a, b: Proc, key: Sort_Key) -> bool {
		switch key {
		case .Cpu:  return a.cpu > b.cpu || (a.cpu == b.cpu && a.rss_kb > b.rss_kb)
		case .Mem:  return a.rss_kb > b.rss_kb
		case .Pid:  return a.pid < b.pid
		case .Name: return strings.to_lower(a.name, context.temp_allocator) < strings.to_lower(b.name, context.temp_allocator)
		}
		return false
	}
	ctx := struct { key: Sort_Key, reverse: bool }{key, reverse}
	context.user_ptr = &ctx
	slice.sort_by(procs, proc(a, b: Proc) -> bool {
		c := (^struct { key: Sort_Key, reverse: bool })(context.user_ptr)
		return less(b, a, c.key) if c.reverse else less(a, b, c.key)
	})
}

@(private = "file")
usage :: proc(prev, cur: Cpu_Times) -> f64 {
	dt := f64(cur.total - min(cur.total, prev.total))
	if dt <= 0 { return 0 }
	return clamp(100 * f64(cur.busy - min(cur.busy, prev.busy)) / dt, 0, 100)
}

@(private = "file")
parse_cpu_line :: proc(line: string) -> Cpu_Times {
	f := strings.fields(line, context.temp_allocator)
	t: Cpu_Times
	idle: u64
	for v, i in f[1:] {
		n := parse_u64(v)
		if i >= 8 { break } // guest time is already counted in user
		t.total += n
		if i == 3 || i == 4 { idle += n } // idle, iowait
	}
	t.busy = t.total - idle
	return t
}

@(private = "file")
push :: proc(hist: ^[dynamic]f64, v: f64) {
	append(hist, v)
	if len(hist) > HISTORY {
		remove_range(hist, 0, len(hist) - HISTORY)
	}
}

@(private = "file")
cpu_model :: proc() -> string {
	for line in strings.split_lines(read("/proc/cpuinfo"), context.temp_allocator) {
		if strings.has_prefix(line, "model name") {
			_, _, v := strings.partition(line, ":")
			return strings.trim_space(v)
		}
	}
	return "cpu"
}

// The CPU package temperature: a hwmon chip known to be the CPU, else the
// first thermal zone.
@(private = "file")
find_temp_sensor :: proc() -> string {
	entries, _ := os.read_all_directory_by_path("/sys/class/hwmon", context.temp_allocator)
	for e in entries {
		name := strings.trim_space(read(join(e.fullpath, "name")))
		switch name {
		case "coretemp", "k10temp", "zenpower", "cpu_thermal", "acpitz":
			path := join(e.fullpath, "temp1_input")
			if read(path) != "" && name != "acpitz" { return path }
		}
	}
	if read("/sys/class/thermal/thermal_zone0/temp") != "" {
		return "/sys/class/thermal/thermal_zone0/temp"
	}
	return ""
}

@(private = "file")
find_battery :: proc() -> string {
	entries, _ := os.read_all_directory_by_path("/sys/class/power_supply", context.temp_allocator)
	for e in entries {
		if strings.has_prefix(e.name, "BAT") { return e.fullpath }
	}
	return ""
}

@(private = "file")
load_users :: proc(s: ^System) {
	for line in strings.split_lines(read("/etc/passwd"), context.temp_allocator) {
		f := strings.split(line, ":", context.temp_allocator)
		if len(f) < 3 { continue }
		uid, ok := strconv.parse_uint(f[2])
		if ok { s.users[u32(uid)] = strings.clone(f[0]) }
	}
}

// Whole file as a string in the temp allocator; "" if it can't be read.
read :: proc(path: string) -> string {
	data, err := os.read_entire_file(path, context.temp_allocator)
	return string(data) if err == nil else ""
}

@(private = "file")
join :: proc(dir, name: string) -> string {
	return strings.concatenate({dir, "/", name}, context.temp_allocator)
}

@(private = "file")
join_all :: proc(parts: ..string) -> string {
	return strings.concatenate(parts, context.temp_allocator)
}

@(private = "file")
parse_u64 :: proc(s: string) -> u64 {
	v, _ := strconv.parse_u64(s)
	return v
}
