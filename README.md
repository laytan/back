# Obacktracing

An abstraction around the libc backtrace API for Odin providing manual backtraces and a tracking allocator that keeps backtraces.

In debug mode, the `backtrace_message` and `backtrace_messages` will try to use the debug information to get source files and line numbers.
When not in debug mode, you will get the memory addresses of the stack locations.

I think this only works on unix.

## Manual

```odin
package manual

import "core:fmt"

import bt "obacktracing"

main :: proc() {
	backtrace, size := bt.backtrace_get(16)
	defer bt.backtrace_delete(backtrace)
	messages := bt.backtrace_messages(backtrace, size)
	defer delete(messages)

	fmt.println("[back trace]")
	for message in messages {
		defer delete(message)
		fmt.printf("    %s\n", message)
	}
}

// $ odin run examples/manual.odin -file -debug
// [back trace]
//     /home/laytan/projects/obacktracing/examples/manual.odin:8
//     /home/laytan/third-party/Odin/core/runtime/entry_unix.odin:30
//     /lib/x86_64-linux-gnu/libc.so.6(+0x29d90) [0x7f5b70629d90]
//     /lib/x86_64-linux-gnu/libc.so.6(__libc_start_main+0x80) [0x7f5b70629e40]
//     /home/laytan/projects/obacktracing/manual.bin() [0x401205]
```

## Tracking Allocator

```odin
package main

import "core:fmt"

import bt "obacktracing"

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

// /home/laytan/projects/obacktracing/examples/allocator/main.odin(7:10) leaked 8 bytes
// [stack trace]
//     /home/laytan/third-party/Odin/core/runtime/internal.odin:138
//     /home/laytan/third-party/Odin/core/runtime/core_builtin.odin:248
//     /home/laytan/third-party/Odin/core/runtime/core_builtin.odin:244
//     /home/laytan/projects/obacktracing/examples/allocator/main.odin:7
//     /home/laytan/projects/obacktracing/examples/allocator/main.odin:18
//     /home/laytan/third-party/Odin/core/runtime/entry_unix.odin:30
//     /lib/x86_64-linux-gnu/libc.so.6(+0x29d90) [0x7fae08429d90]
//     /lib/x86_64-linux-gnu/libc.so.6(__libc_start_main+0x80) [0x7fae08429e40]
// /home/laytan/pro/home/laytan/projects/obacktracing/examples/allocator/main.odin(8:5) allocation 64 was freed badly
// [stack trace]
//     /home/laytan/third-party/Odin/core/runtime/internal.odin:159
//     /home/laytan/projects/obacktracing/examples/allocator/main.odin:9
//     /home/laytan/projects/obacktracing/examples/allocator/main.odin:18
//     /home/laytan/third-party/Odin/core/runtime/entry_unix.odin:30
//     /lib/x86_64-linux-gnu/libc.so.6(+0x29d90) [0x7fae08429d90]
//     /lib/x86_64-linux-gnu/libc.so.6(__libc_start_main+0x80) [0x7fae08429e40]
//     /home/laytan/projects/obacktracing/allocator() [0x401205]jects/obacktracing/allocator() [0x401205]
```
