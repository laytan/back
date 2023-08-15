# Obacktracing

An abstraction around the libc backtrace API for Odin providing manual backtraces and a tracking allocator that keeps backtraces.

In debug mode, the `backtrace_message` and `backtrace_messages` will try to use the debug information to get source files and line numbers.
When not in debug mode, you will get the memory addresses of the stack locations.

This is confirmed to work on Linux and should work on MacOS,
although when I tested it on ARM, only 1 stack frame was ever returned, this probably needs some flags.

## Manual

```odin
package manual

import "core:fmt"

import bt "../.."

main :: proc() {
	trace := bt.backtrace_get(16)
	defer bt.backtrace_delete(trace)

	messages, err := bt.backtrace_messages(trace)
	fmt.assertf(err == nil, "err: %v", err)
	defer bt.messages_delete(messages)

	fmt.println("[back trace]")
	for message in messages {
		fmt.printf("    %s - %s\n", message.symbol, message.location)
	}
}

// $ odin run examples/manual -debug
// [back trace]
//     obacktracing.backtrace_get - /home/laytan/projects/obacktracing/obacktracing.odin:39
//     manual.main - /home/laytan/projects/obacktracing/examples/manual/main.odin:8
//     main - /home/laytan/third-party/Odin/core/runtime/entry_unix.odin:30
//     ?? - /lib/x86_64-linux-gnu/libc.so.6(+0x29d90) [0x7f42bc029d90]
//     ?? - /lib/x86_64-linux-gnu/libc.so.6(__libc_start_main+0x80) [0x7f42bc029e40]
//     _start - /home/laytan/projects/obacktracing/manual() [0x401135]
```

## Tracking Allocator

```odin
package main

import bt "../.."

_main :: proc() {
	_ = new(int)
	free(rawptr(uintptr(100)))
}

main :: proc() {
	track: bt.Tracking_Allocator
	bt.tracking_allocator_init(&track, 16, context.allocator)
	bt.tracking_allocator_destroy(&track)
	defer bt.tracking_allocator_destroy(&track)
	context.allocator = bt.tracking_allocator(&track)

	_main()

	bt.tracking_allocator_print_results(&track)
}

// $ odin run examples/allocator -debug
// /home/laytan/projects/obacktracing/examples/allocator/main.odin(8:7) leaked 8 bytes
// [back trace]
//     runtime.mem_alloc_bytes - /home/laytan/third-party/Odin/core/runtime/internal.odin:138
//     runtime.new_aligned-13495 - /home/laytan/third-party/Odin/core/runtime/core_builtin.odin:248
//     runtime.new-13401 - /home/laytan/third-party/Odin/core/runtime/core_builtin.odin:244
//     main._main - /home/laytan/projects/obacktracing/examples/allocator/main.odin:8
//     main.main - /home/laytan/projects/obacktracing/examples/allocator/main.odin:21
//     main - /home/laytan/third-party/Odin/core/runtime/entry_unix.odin:30
//     ?? - /lib/x86_64-linux-gnu/libc.so.6(+0x29d90) [0x7ff775229d90]
//     ?? - /lib/x86_64-linux-gnu/libc.so.6(__libc_start_main+0x80) [0x7ff775229e40]
//     _start - /home/laytan/projects/obacktracing/allocator() [0x401135]
//
//
// /home/laytan/projects/obacktracing/examples/allocator/main.odin(9:2) allocation 64 was freed badly
// [back trace]
//     runtime.mem_free - /home/laytan/third-party/Odin/core/runtime/internal.odin:159
//     main._main - /home/laytan/projects/obacktracing/examples/allocator/main.odin:10
//     main.main - /home/laytan/projects/obacktracing/examples/allocator/main.odin:21
//     main - /home/laytan/third-party/Odin/core/runtime/entry_unix.odin:30
//     ?? - /lib/x86_64-linux-gnu/libc.so.6(+0x29d90) [0x7ff775229d90]
//     ?? - /lib/x86_64-linux-gnu/libc.so.6(__libc_start_main+0x80) [0x7ff775229e40]
//     _start - /home/laytan/projects/obacktracing/allocator() [0x401135]
```
