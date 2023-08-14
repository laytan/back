package main

import "core:fmt"

import bt "../.."

_main :: proc() {
	c := new(int)
	free(rawptr(uintptr(100)))
}

main :: proc() {
	track: bt.Backtrace_Tracking_Allocator
	bt.backtrace_tracking_allocator_init(&track, context.allocator)
	defer bt.backtrace_tracking_allocator_destroy(&track)

	context.allocator = bt.backtrace_tracking_allocator(&track)
	_main()
	context.allocator = track.backing

	for _, leak in track.allocation_map {
		fmt.printf("\x1b[31m%v leaked %v bytes\x1b[0m\n", leak.location, leak.size)
		fmt.println("[back trace]")
		msgs := bt.backtrace_messages(leak.backtrace, leak.backtrace_size)
		for msg in msgs[2:] {
			fmt.printf("    %s\n", msg)
		}
	}

	for bad_free in track.bad_free_array {
		fmt.printf(
			"\x1b[31m%v allocation %p was freed badly\x1b[0m\n",
			bad_free.location,
			bad_free.memory,
		)
		fmt.println("[back trace]")
		msgs := bt.backtrace_messages(bad_free.backtrace, bad_free.backtrace_size)
		for msg in msgs[2:] {
			fmt.printf("    %s\n", msg)
		}
	}
}
