package main

// System statistics for the monitor.
//
// Linux reads /proc and /sys, and macOS builds the same reader (with no live
// stats, since there is no /proc). FreeBSD uses the standard sysctl, ps,
// netstat and swapinfo tools. The platform pieces live in sysinfo_procfs.odin
// and sysinfo_freebsd.odin.

import "core:mem/virtual"
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
	user:    string, // in System.users (Linux) or System.proc_arena (FreeBSD)
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

usage :: proc(prev, cur: Cpu_Times) -> f64 {
	dt := f64(cur.total - min(cur.total, prev.total))
	if dt <= 0 { return 0 }
	return clamp(100 * f64(cur.busy - min(cur.busy, prev.busy)) / dt, 0, 100)
}

push :: proc(hist: ^[dynamic]f64, v: f64) {
	append(hist, v)
	if len(hist) > HISTORY {
		remove_range(hist, 0, len(hist) - HISTORY)
	}
}

parse_u64 :: proc(s: string) -> u64 {
	v, _ := strconv.parse_u64(s)
	return v
}
