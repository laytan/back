package back

import "core:fmt"
import "core:io"
import "core:os"
import "core:runtime"
import "core:text/table"

BACKTRACE_SIZE :: #config(BACKTRACE_SIZE, 16)

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

EAGAIN :: os.EAGAIN when ODIN_OS != .Windows else 5
ENOMEM :: os.ENOMEM when ODIN_OS != .Windows else 6
EFAULT :: os.EFAULT when ODIN_OS != .Windows else 7
EMFILE :: os.EMFILE when ODIN_OS != .Windows else 8
ENFILE :: os.ENFILE when ODIN_OS != .Windows else 9
ENOSYS :: os.ENOSYS when ODIN_OS != .Windows else 10

Lines_Error :: enum {
	None,
	Parse_Address_Fail,
	Addr2line_Unexpected_EOF,
	Addr2line_Output_Error,
	Addr2line_Unresolved,

	Fork_Limited         = int(EAGAIN),
	Out_Of_Memory        = int(ENOMEM),
	Invalid_Fd           = int(EFAULT),
	Pipe_Process_Limited = int(EMFILE),
	Pipe_System_Limited  = int(ENFILE),
	Fork_Not_Supported   = int(ENOSYS),

	Info_Not_Found,
}

trace :: #force_no_inline proc() -> (bt: Trace_Const) {
	bt.len = #force_inline _trace(bt.trace[:])
	return
}

trace_n :: #force_no_inline proc(max_len: i32, allocator := context.allocator) -> Trace {
	context.allocator = allocator
	bt := make([]Trace_Entry, max_len)
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

lines_n :: proc(bt: Trace, allocator := context.allocator) -> (out: []Line, err: Lines_Error) {
	context.allocator = allocator
	return _lines(bt)
}

lines_const :: proc(bt: Trace_Const, allocator := context.allocator) -> (out: []Line, err: Lines_Error) {
	context.allocator = allocator
	bt := bt
	return _lines(bt.trace[:bt.len])
}

lines_destroy :: proc(lines: []Line, allocator := context.allocator) {
	context.allocator = allocator
	_lines_destroy(lines)
}

assertion_failure_proc :: proc(prefix, message: string, loc: runtime.Source_Code_Location) -> ! {
	t := trace()
    lines, err := lines(t.trace[:t.len])
    if err != nil {
        fmt.eprintf("could not get backtrace for assertion failure: %v\n", err)
        runtime.default_assertion_failure_proc(prefix, message, loc)
    } else {
        fmt.eprintln("[back trace]")
		print(lines)
        runtime.default_assertion_failure_proc(prefix, message, loc)
    }
}

register_segfault_handler :: proc() {
	_register_segfault_handler()
}

print :: proc(lines: []Line, padding := "    ", w: Maybe(io.Writer) = nil, no_temp_guard := false) {
	w := w.? or_else os.stream_from_handle(os.stderr)

	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD(ignore=no_temp_guard)

	tbl := table.init(&table.Table{}, context.temp_allocator, context.temp_allocator)

	for line in lines {
		table.row(tbl, padding, line.symbol, " - ", line.location)
	}

	table.build(tbl)

	for row in 0..<tbl.nr_rows {
		for col in 0..<tbl.nr_cols {
			table.write_table_cell(w, tbl, row, col)
		}
		io.write_byte(w, '\n')
	}
}
