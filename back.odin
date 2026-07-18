#+vet explicit-allocators
package back

import "base:runtime"

import "core:fmt"
import "core:io"
import "core:os"
import "core:text/table"

// Size of a constant backtrace, as used by the allocator for example.
BACKTRACE_SIZE :: #config(BACKTRACE_SIZE, 16)

// For targets that do not have native support (using debug info),
// backtraces are done through instrumentation, Odin only allows one enter/exit instrumentation
// procedure though, so you can set this to true, add your own instrumentation procs, and have
// them call `back.other_instrumentation_enter` and `back.other_instrumentation_exit` to hook
// up the backtraces.
//
// The custom proc must have `#force_inline`.
OTHER_CUSTOM_INSTRUMENTATION :: #config(BACK_OTHER_CUSTOM_INSTRUMENTATION, false)

// Force the fallback instrumentation based implementation instead of debug info based.
FORCE_FALLBACK :: #config(BACK_FORCE_FALLBACK, false)

USE_FALLBACK :: FORCE_FALLBACK || (ODIN_OS != .Darwin && ODIN_OS != .Linux && ODIN_OS != .Windows)

Trace :: []Trace_Entry

Trace_Const :: struct {
	trace: [BACKTRACE_SIZE]Trace_Entry,
	len:   int,
}

// Platform specific.
Trace_Entry :: _Trace_Entry

Line :: struct {
	location: string,
	symbol:   string,
}

Lines_Error :: enum {
	None,
	Parse_Address_Fail,
	Addr2line_Unexpected_EOF,
	Addr2line_Output_Error,
	Addr2line_Unresolved,
	Addr2line_Process_Error,

	Fork_Limited         = _LINES_ERROR_FORK_LIMITED,
	Out_Of_Memory        = _LINES_ERROR_OUT_OF_MEMORY,
	Invalid_Fd           = _LINES_ERROR_INVALID_FD,
	Pipe_Process_Limited = _LINES_ERROR_PIPE_PROCESS_LIMITED,
	Pipe_System_Limited  = _LINES_ERROR_PIPE_SYSTEM_LIMITED,
	Fork_Not_Supported   = _LINES_ERROR_FORK_NOT_SUPPORTED,

	Info_Not_Found,
}

trace :: #force_no_inline proc() -> (bt: Trace_Const) {
	bt.len = #force_inline _trace(bt.trace[:])
	return
}

trace_n :: #force_no_inline proc(max_len: i32, allocator := context.allocator) -> Trace {
	bt := make([]Trace_Entry, max_len, allocator)
	n  := #force_inline _trace(bt[:])
	return bt[:n]
}

trace_fill :: #force_no_inline proc(buf: Trace) -> int {
	return #force_inline _trace(buf)
}

trace_n_destroy :: proc(b: Trace, allocator := context.allocator) {
	delete(b, allocator)
}

// Processes the message trying to get more/useful information.
// This adds file and line information if the program is running in debug mode.
//
// If an error is returned the original message will be the result and is save to use.
lines :: proc {
	lines_n,
	lines_const,
}

lines_n :: proc(bt: Trace, allocator := context.allocator, temp_allocator := context.temp_allocator) -> (out: []Line, err: Lines_Error) {
	return _lines(bt, allocator, temp_allocator)
}

lines_const :: proc(bt: Trace_Const, allocator := context.allocator, temp_allocator := context.temp_allocator) -> (out: []Line, err: Lines_Error) {
	bt := bt
	return _lines(bt.trace[:bt.len], allocator, temp_allocator)
}

lines_destroy :: proc(lines: []Line, allocator := context.allocator) {
	_lines_destroy(lines, allocator)
}

assertion_failure_proc :: proc(prefix, message: string, loc: runtime.Source_Code_Location) -> ! {
	{
		runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()

		lines, err := lines(trace(), context.temp_allocator, context.temp_allocator)
		if err != nil {
			fmt.eprintf("could not get backtrace for assertion failure: %v\n", err)
		} else {
			fmt.eprintln("[back trace]")
			print(lines, temp_allocator=context.temp_allocator)
		}
	}

	runtime.default_assertion_failure_proc(prefix, message, loc)
}

register_segfault_handler :: proc() {
	_register_segfault_handler()
}

print :: proc(lines: []Line, padding := "    ", w: Maybe(io.Writer) = nil, temp_allocator := context.temp_allocator) {
	w := w.? or_else os.to_writer(os.stderr)

	tbl := table.init(&table.Table{}, temp_allocator, temp_allocator)

	for line in lines {
		table.row(tbl, padding, line.symbol, " - ", line.location)
	}

	table.build(tbl, table.unicode_width_proc)

	for row in 0..<tbl.nr_rows {
		for col in 0..<tbl.nr_cols {
			table.write_table_cell(w, tbl, row, col)
		}
		io.write_byte(w, '\n')
	}
}
