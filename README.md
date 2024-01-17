# Back

Backtraces for Odin on the major platforms (MacOS, Linux, Windows).

For Windows support, all credit goes to [DaseinPhaos/pdb](https://github.com/DaseinPhaos/pdb).

NOTE: The pdb package allocates a lot of stuff and does not really provide a way of deleting the allocations, so, before calling into the package, this package sets it to use the `context.temporary_allocator`.

In debug mode, the `back.lines` will try to use the debug information to get source files and line numbers.
When not in debug mode, you will get greatly reduced information.

## Installation

Back does not use any libraries or external dependencies not pre-installed on the OS.

On Linux, the `addr2line` command is invoked, which comes pre-installed (maybe in binutils).

The `addr2line` command can be changed by setting the `-define:BACK_ADDR2LINE_PATH=your/atos` flag.

The path to the running binary is also needed for this command, this is `os.args[0]` by default and to my knowledge is always correct.
Nevertheless it can be changed with the `-define:BACK_PROGRAM=path/to/binary` flag.

To change the size (amount of stackframes to print) in places where this can't be set directly, you can use the `-define:BACKTRACE_SIZE=16`.

## Manual

```odin
package manual

import "core:fmt"

import back "../.."

main :: proc() {
	// Allocates for 16 frames.
	bt := back.trace_n(16)
	print(bt)

	// Or, doesn't allocate, returns `-define:BACKTRACE_SIZE` frames.
	btc := back.trace()
	print(btc.trace[:btc.len])

	// Or, fill in a slice.
	bt = make(back.Trace, 16)
	bt = bt[:back.trace_fill(bt)]
	print(bt)
}

print :: proc(bt: back.Trace) {
	lines, err := back.lines(bt)
	if err != nil {
		fmt.eprintf("Could not retrieve backtrace lines: %v\n", err)
	} else {
		defer back.lines_destroy(lines)

		fmt.eprintln("[back trace]")
		back.print(lines)
	}
}

// [back trace]
//     back.trace_n - /Users/laytan/projects/back/back.odin:59
//     manual.main  - /Users/laytan/projects/back/examples/manual/main.odin:9
//     main         - /Users/laytan/third-party/Odin/core/runtime/entry_unix.odin:53
// [back trace]
//     back.trace  - /Users/laytan/projects/back/back.odin:52
//     manual.main - /Users/laytan/projects/back/examples/manual/main.odin:13
//     main        - /Users/laytan/third-party/Odin/core/runtime/entry_unix.odin:53
// [back trace]
//     back.trace_fill - /Users/laytan/projects/back/back.odin:64
//     manual.main     - /Users/laytan/projects/back/examples/manual/main.odin:18
//     main            - /Users/laytan/third-party/Odin/core/runtime/entry_unix.odin:53
```

## Tracking Allocator

```odin
package main

import "back"

_main :: proc() {
	_ = new(int)
	free(rawptr(uintptr(100)))
}

main :: proc() {
	track: back.Tracking_Allocator
	back.tracking_allocator_init(&track, context.allocator)
	defer back.tracking_allocator_destroy(&track)

	context.allocator = back.tracking_allocator(&track)
	defer back.tracking_allocator_print_results(&track)

	_main()
}

// /Users/laytan/projects/back/examples/allocator/main.odin(6:6) leaked 8b
// [back trace]
//     back.trace                   - /Users/laytan/projects/back/back.odin:52
//     back.tracking_allocator_proc - /Users/laytan/projects/back/allocator.odin:129
//     runtime.mem_alloc_bytes      - /Users/laytan/third-party/Odin/core/runtime/internal.odin:141
//     runtime.new_aligned-13136    - /Users/laytan/third-party/Odin/core/runtime/core_builtin.odin:250
//     runtime.new-13097            - /Users/laytan/third-party/Odin/core/runtime/core_builtin.odin:246
//     main._main                   - /Users/laytan/projects/back/examples/allocator/main.odin:6
//     main.main                    - /Users/laytan/projects/back/examples/allocator/main.odin:18
//     main                         - /Users/laytan/third-party/Odin/core/runtime/entry_unix.odin:53
//
//
// /Users/laytan/projects/back/examples/allocator/main.odin(7:2) allocation 64 was freed badly
// [back trace]
//     back.trace                   - /Users/laytan/projects/back/back.odin:52
//     back.tracking_allocator_proc - /Users/laytan/projects/back/allocator.odin:102
//     runtime.mem_free             - /Users/laytan/third-party/Odin/core/runtime/internal.odin:162
//     main._main                   - /Users/laytan/projects/back/examples/allocator/main.odin:8
//     main.main                    - /Users/laytan/projects/back/examples/allocator/main.odin:18
//     main                         - /Users/laytan/third-party/Odin/core/runtime/entry_unix.odin:53
```

## Printing a backtrace on assertion failures / panics

```odin
package main

import "back"

main :: proc() {
    context.assertion_failure_proc = back.assertion_failure_proc
    assert(3 == 2)
}

// [back trace]
//     back.trace                  - /Users/laytan/projects/back/back.odin:52
//     back.assertion_failure_proc - /Users/laytan/projects/back/back.odin:97
//     runtime.assert.internal-0   - /Users/laytan/third-party/Odin/core/runtime/core_builtin.odin:818
//     runtime.assert              - /Users/laytan/third-party/Odin/core/runtime/core_builtin.odin:820
//     main.main                   - /Users/laytan/projects/back/examples/assert_backtrace/main.odin:8
//     main                        - /Users/laytan/third-party/Odin/core/runtime/entry_unix.odin:53
// /Users/laytan/projects/back/examples/assert_backtrace/main.odin(7:5) runtime assertion
```

## Printing a backtrace on segmentation faults

```odin
package main

import "back"

main :: proc() {
	back.register_segfault_handler()

	ptr: ^int
	bad := ptr^ + 2
	_ = bad
}

// Segmentation Fault
// [back trace]
//     back.trace                            - /Users/laytan/projects/back/back.odin:52
//     back.register_segfault_handler$anon-1 - /Users/laytan/projects/back/back.odin:114
//     ??                                    - ??
//     main.main                             - /Users/laytan/projects/back/examples/segfault/main.odin:8
```
