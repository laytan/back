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
