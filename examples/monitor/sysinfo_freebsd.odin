#+build freebsd
package main

// FreeBSD implementation: /proc is not mounted by default, so the monitor
// shells out to the standard tools. Everything here is plain Odin: no foreign
// imports and no direct libc bindings.

import "core:mem/virtual"
import "core:os"
import "core:strconv"
import "core:strings"
import "core:time"

OS_NAME :: "freebsd"

system_init :: proc(s: ^System) {
	_ = virtual.arena_init_growing(&s.proc_arena)

	host, kernel, model := "", "", "cpu"
	for line in strings.split_lines(run("/sbin/sysctl", "kern.hostname", "kern.osrelease", "hw.model"), context.temp_allocator) {
		key, _, val := strings.partition(line, ":")
		switch strings.trim_space(key) {
		case "kern.hostname": host = strings.trim_space(val)
		case "kern.osrelease": kernel = strings.trim_space(val)
		case "hw.model": model = strings.trim_space(val)
		}
	}
	s.host = strings.clone(host)
	s.kernel = strings.clone(kernel)
	s.cpu_model = strings.clone(model)
	s.temp = -1
	s.battery = -1
	sample_system(s)
	sample_procs(s)
}

// CPU, memory, network, load, sensors. One sysctl call plus one netstat call.
sample_system :: proc(s: ^System) {
	out := run("/sbin/sysctl",
		"kern.cp_time",
		"kern.cp_times",
		"hw.physmem",
		"hw.pagesize",
		"vm.stats.vm.v_free_count",
		"vm.stats.vm.v_inactive_count",
		"vm.stats.vm.v_cache_count",
		"vm.stats.vm.v_laundry_count",
		"vm.loadavg",
		"kern.boottime",
		"dev.cpu",
		"hw.acpi.thermal",
		"hw.acpi.battery",
	)
	if out == "" { return }

	physmem, pagesize: u64
	free_pages, inactive_pages, cache_pages, laundry_pages: u64
	load: [3]f64
	boot_sec: i64
	temp := -1.0
	battery := -1
	charging := false

	for line in strings.split_lines(out, context.temp_allocator) {
		key, _, val := strings.partition(line, ":")
		key = strings.trim_space(key)
		val = strings.trim_space(val)
		switch key {
		case "kern.cp_time":
			t := parse_cp_time(val)
			s.cpu = usage(s.prev_cpu, t)
			s.prev_cpu = t
		case "kern.cp_times":
			parse_cp_times(s, val)
		case "hw.physmem":
			physmem = parse_u64(val)
		case "hw.pagesize":
			pagesize = parse_u64(val)
		case "vm.stats.vm.v_free_count":
			free_pages = parse_u64(val)
		case "vm.stats.vm.v_inactive_count":
			inactive_pages = parse_u64(val)
		case "vm.stats.vm.v_cache_count":
			cache_pages = parse_u64(val)
		case "vm.stats.vm.v_laundry_count":
			laundry_pages = parse_u64(val)
		case "vm.loadavg":
			load = parse_loadavg(val)
		case "kern.boottime":
			boot_sec = parse_boottime(val)
		case "hw.acpi.battery.life":
			battery = int(parse_u64(val))
		case "hw.acpi.battery.state":
			charging = (parse_u64(val) & 2) != 0
		}
		if strings.has_suffix(key, ".temperature") {
			if t, ok := parse_temp(val); ok && t > temp { temp = t }
		}
	}

	s.temp = temp
	if temp >= 0 { push(&s.temp_hist, temp) }
	s.battery = battery
	s.charging = charging

	if pagesize == 0 { pagesize = 4096 }
	page_kb := pagesize / 1024
	s.mem_total = physmem / 1024
	avail_pages := free_pages + inactive_pages + cache_pages + laundry_pages
	s.mem_avail = avail_pages * page_kb
	s.mem_cached = (inactive_pages + cache_pages + laundry_pages) * page_kb
	push(&s.mem_hist, 100 * f64(s.mem_total - s.mem_avail) / max(f64(s.mem_total), 1))

	if boot_sec > 0 {
		s.uptime = max(f64(time.time_to_unix(time.now()) - boot_sec), 0)
	}
	s.load = load
	push(&s.cpu_hist, s.cpu)
	sample_net(s)
}

// Walks the process table with ps(1). CPU% comes from ps, which is a decaying
// average, unlike the interval value Linux computes.
sample_procs :: proc(s: ^System) {
	out := run("/bin/ps", "-axo", "pid,user,stat,nlwp,pcpu,rss,comm")
	if out == "" { return }

	virtual.arena_free_all(&s.proc_arena)
	names := virtual.arena_allocator(&s.proc_arena)
	clear(&s.procs)
	s.threads = 0
	running := 0

	for line, i in strings.split_lines(out, context.temp_allocator) {
		if i == 0 || strings.trim_space(line) == "" { continue }
		f := strings.fields(line, context.temp_allocator)
		if len(f) < 7 { continue }
		// FreeBSD's idle kernel thread accumulates all idle CPU time, so it
		// would always dominate the table. top(1) hides it too.
		if f[1] == "root" && f[6] == "idle" { continue }
		pid, ok := strconv.parse_int(f[0])
		if !ok { continue }

		p: Proc
		p.pid = pid
		p.user = strings.clone(f[1], names)
		if len(f[2]) > 0 {
			p.state = f[2][0]
			if p.state == 'R' { running += 1 }
		}
		p.threads = int(parse_u64(f[3]))
		p.cpu, _ = strconv.parse_f64(f[4])
		p.rss_kb = parse_u64(f[5])
		p.name = strings.join(f[6:], " ", names)
		s.threads += p.threads
		append(&s.procs, p)
	}
	s.running = running
	sample_swap(s)
}

@(private = "file")
run :: proc(args: ..string) -> string {
	desc := os.Process_Desc {
		command = args,
		env     = []string{"LC_ALL=C"},
	}
	_, out, _, err := os.process_exec(desc, context.temp_allocator)
	if err != nil { return "" }
	return string(out)
}

@(private = "file")
parse_cp_time :: proc(val: string) -> Cpu_Times {
	f := strings.fields(val, context.temp_allocator)
	t: Cpu_Times
	idle: u64
	for v, i in f {
		if i >= 5 { break }
		n := parse_u64(v)
		t.total += n
		if i == 4 { idle = n } // CP_IDLE
	}
	t.busy = t.total - idle
	return t
}

@(private = "file")
parse_cp_times :: proc(s: ^System, val: string) {
	f := strings.fields(val, context.temp_allocator)
	core := 0
	for i := 0; i + 4 < len(f); i += 5 {
		total, idle: u64
		for j in 0 ..< 5 {
			n := parse_u64(f[i + j])
			total += n
			if j == 4 { idle = n }
		}
		if total == 0 { continue } // absent CPU slot

		t := Cpu_Times{busy = total - idle, total = total}
		if core >= len(s.cores) {
			append(&s.cores, 0)
			append(&s.prev_cores, t)
		}
		s.cores[core] = usage(s.prev_cores[core], t)
		s.prev_cores[core] = t
		core += 1
	}
	if core < len(s.cores) {
		resize(&s.cores, core)
		resize(&s.prev_cores, core)
	}
	s.ncores = max(core, 1)
}

@(private = "file")
parse_loadavg :: proc(val: string) -> [3]f64 {
	load: [3]f64
	v := strings.trim_space(val)
	v = strings.trim_prefix(v, "{")
	v = strings.trim_suffix(v, "}")
	f := strings.fields(v, context.temp_allocator)
	for i in 0 ..< min(len(f), 3) {
		load[i], _ = strconv.parse_f64(f[i])
	}
	return load
}

@(private = "file")
parse_boottime :: proc(val: string) -> i64 {
	_, _, rest := strings.partition(val, "sec = ")
	if rest == "" { return 0 }
	sec, _, _ := strings.partition(rest, ",")
	v, ok := strconv.parse_i64(strings.trim_space(sec))
	return v if ok else 0
}

@(private = "file")
parse_temp :: proc(val: string) -> (t: f64, ok: bool) {
	v := strings.trim_space(val)
	switch {
	case strings.has_suffix(v, "C"):
		t, ok = strconv.parse_f64(strings.trim_suffix(v, "C"))
	case strings.has_suffix(v, "K"):
		k: f64
		k, ok = strconv.parse_f64(strings.trim_suffix(v, "K"))
		if ok { t = k - 273.15 }
	case:
		t, ok = strconv.parse_f64(v)
	}
	return
}

// netstat -ibn: sum the <Link#N> rows, skipping loopback.
@(private = "file")
sample_net :: proc(s: ^System) {
	out := run("/usr/bin/netstat", "-ibn")
	if out == "" {
		push(&s.rx_hist, s.rx_rate)
		push(&s.tx_hist, s.tx_rate)
		return
	}

	rx, tx: u64
	for line in strings.split_lines(out, context.temp_allocator) {
		f := strings.fields(line, context.temp_allocator)
		if len(f) < 11 { continue }
		if f[0] == "lo0" || f[0] == "lo" { continue }
		if !strings.has_prefix(f[2], "<Link#") { continue }
		rx += parse_u64(f[7])  // Ibytes
		tx += parse_u64(f[10]) // Obytes
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
}

// swapinfo -k: Device 1K-blocks Used Avail Capacity.
@(private = "file")
sample_swap :: proc(s: ^System) {
	total, avail: u64
	for line in strings.split_lines(run("/usr/sbin/swapinfo", "-k"), context.temp_allocator) {
		if strings.has_prefix(line, "Device") { continue }
		f := strings.fields(line, context.temp_allocator)
		if len(f) < 4 { continue }
		total += parse_u64(f[1])
		avail += parse_u64(f[3])
	}
	s.swap_total = total
	s.swap_free = avail
}
