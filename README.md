# Obacktracing

Backtrace support for the Odin programming language.

For best results, compile with the `-debug` flag.

- Windows: parses pdb with the help of [DaseinPhaos/pdb](https://github.com/DaseinPhaos/pdb)
- Linux: uses the libc backtrace API in combination with the `addr2line` command
- MacOS: uses the libc backtrace API in combination with the `atos` command

NOTE: The pdb package allocates a lot of stuff and does not really provide a way of deleting the allocations, so, before calling into the package, this package sets it to use the `context.temporary_allocator`.

In debug mode, the `backtrace_message` and `backtrace_messages` will try to use the debug information to get source files and line numbers.
When not in debug mode, you will (at best) get the memory addresses of the stack locations.

## Installation

`git clone`

## Manual

```odin
package manual

import "core:fmt"

import bt "obacktracing"

main :: proc() {
	trace := bt.backtrace_get(16)
	defer bt.backtrace_delete(trace)

	messages, err := bt.backtrace_messages(trace)
	fmt.assertf(err == nil, "err: %v", err)
	defer bt.messages_delete(messages)

	fmt.println("[back trace]")
	bt.format(messages)
}

// $ odin run examples/manual -debug # Output on MacOS
// [back trace]
//     obacktracing._backtrace_get-965 - /Users/laytan/projects/obacktracing/obacktracing_unix.odin:45
//     obacktracing.backtrace_get      - /Users/laytan/projects/obacktracing/obacktracing.odin:12
//     manual.main                     - /Users/laytan/projects/obacktracing/examples/manual/main.odin:8
//     main                            - /Users/laytan/Odin/core/runtime/entry_unix.odin:52
//     ??                              - 4   dyld                                0x0000000187595058 start + 2224
```

## Tracking Allocator

```odin
package main

import bt "obacktracing"

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

// $ odin run examples/allocator -debug # Output on MacOS
// /Users/laytan/projects/obacktracing/examples/allocator/main.odin(6:6) leaked 8 bytes
// [back trace]
//     obacktracing._backtrace_get-1124     - /Users/laytan/projects/obacktracing/obacktracing_unix.odin:45
//     obacktracing.backtrace_get           - /Users/laytan/projects/obacktracing/obacktracing.odin:12
//     obacktracing.tracking_allocator_proc - /Users/laytan/projects/obacktracing/allocator.odin:138
//     runtime.mem_alloc_bytes              - /Users/laytan/Odin/core/runtime/internal.odin:141
//     runtime.new_aligned-13802            - /Users/laytan/Odin/core/runtime/core_builtin.odin:248
//     runtime.new-13779                    - /Users/laytan/Odin/core/runtime/core_builtin.odin:244
//     main._main                           - /Users/laytan/projects/obacktracing/examples/allocator/main.odin:6
//     main.main                            - /Users/laytan/projects/obacktracing/examples/allocator/main.odin:17
//     main                                 - /Users/laytan/Odin/core/runtime/entry_unix.odin:52
//     ??                                   - 9   dyld                                0x0000000187595058 start + 2224
//
//
// /Users/laytan/projects/obacktracing/examples/allocator/main.odin(7:2) allocation 64 was freed badly
// [back trace]
//     obacktracing._backtrace_get-1124     - /Users/laytan/projects/obacktracing/obacktracing_unix.odin:45
//     obacktracing.backtrace_get           - /Users/laytan/projects/obacktracing/obacktracing.odin:12
//     obacktracing.tracking_allocator_proc - /Users/laytan/projects/obacktracing/allocator.odin:111
//     runtime.mem_free                     - /Users/laytan/Odin/core/runtime/internal.odin:162
//     main._main                           - /Users/laytan/projects/obacktracing/examples/allocator/main.odin:8
//     main.main                            - /Users/laytan/projects/obacktracing/examples/allocator/main.odin:17
//     main                                 - /Users/laytan/Odin/core/runtime/entry_unix.odin:52
//     ??                                   - 7   dyld                                0x0000000187595058 start + 2224
```

## Printing a backtrace on assertion failures / panics

```odin
package main

import bt "obacktracing"

main :: proc() {
    context.assertion_failure_proc = bt.assertion_failure_proc
    assert(3 == 2)
}

// $ odin run examples/assert_backtrace -debug # Output on MacOS
// [back trace]
//     obacktracing._backtrace_get-1414    - /Users/laytan/projects/obacktracing/obacktracing_unix.odin:45
//     obacktracing.backtrace_get          - /Users/laytan/projects/obacktracing/obacktracing.odin:12
//     obacktracing.assertion_failure_proc - /Users/laytan/projects/obacktracing/obacktracing.odin:78
//     runtime.assert.internal-0           - /Users/laytan/Odin/core/runtime/core_builtin.odin:813
//     runtime.assert                      - /Users/laytan/Odin/core/runtime/core_builtin.odin:815
//     main.main                           - /Users/laytan/projects/obacktracing/examples/assert_backtrace/main.odin:8
//     main                                - /Users/laytan/Odin/core/runtime/entry_unix.odin:52
//     ??                                  - 7   dyld                                0x0000000187595058 start + 2224
// /Users/laytan/projects/obacktracing/examples/assert_backtrace/main.odin(7:5) runtime assertion
```
