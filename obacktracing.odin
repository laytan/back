package obacktracing

import "core:c/libc"
import "core:fmt"
import "core:io"
import "core:os"
import "core:runtime"
import "core:text/table"

BACKTRACE_SIZE :: #config(BACKTRACE_SIZE, 16)

backtrace_get :: #force_no_inline proc(max_len: i32, allocator := context.allocator) -> Backtrace {
	return #force_inline _backtrace_get(max_len, allocator)
}

backtrace_delete :: proc(b: Backtrace, allocator := context.allocator) {
	_backtrace_delete(b, allocator)
}

Backtrace :: _Backtrace

Message :: struct {
	location: string,
	symbol:   string,
}

messages_delete :: proc(msgs: []Message, allocator := context.allocator) {
	_messages_delete(msgs, allocator)
}

EAGAIN :: os.EAGAIN when ODIN_OS != .Windows else 5
ENOMEM :: os.ENOMEM when ODIN_OS != .Windows else 6
EFAULT :: os.EFAULT when ODIN_OS != .Windows else 7
EMFILE :: os.EMFILE when ODIN_OS != .Windows else 8
ENFILE :: os.ENFILE when ODIN_OS != .Windows else 9
ENOSYS :: os.ENOSYS when ODIN_OS != .Windows else 10

Message_Error :: enum {
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

// Processes the message trying to get more/useful information.
// This adds file and line information if the program is running in debug mode.
//
// If an error is returned the original message will be the result and is save to use.
backtrace_messages :: proc(bt: Backtrace, allocator := context.allocator) -> (out: []Message, err: Message_Error) {
	return _backtrace_messages(bt, allocator)
}

assertion_failure_proc :: proc(prefix, message: string, loc: runtime.Source_Code_Location) -> ! {
    t := backtrace_get(BACKTRACE_SIZE)
    msgs, err := backtrace_messages(t)
    if err != nil {
        fmt.printf("could not get backtrace for assertion failure: %v\n", err)
        runtime.default_assertion_failure_proc(prefix, message, loc)
    } else {
        fmt.println("[back trace]")
		format(msgs)

        runtime.default_assertion_failure_proc(prefix, message, loc)
    }
}

register_segfault_handler :: proc() {
	libc.signal(libc.SIGSEGV, proc "c" (code: i32) {
		context = runtime.default_context()

		backtrace: {
			trace := backtrace_get(BACKTRACE_SIZE)
			defer backtrace_delete(trace)

			messages, err := backtrace_messages(trace)
			if err != nil {
				fmt.eprintf("Segmentation Fault\nCould not get backtrace: %v\n", err)
				break backtrace
			}
			defer messages_delete(messages)

			fmt.eprintln("Segmentation Fault\n[back trace]")
			format(messages)
		}

		os.exit(int(code))
	})
}

format :: proc(msgs: []Message, padding := "    ", w: Maybe(io.Writer) = nil) {
	w := w.? or_else os.stream_from_handle(os.stderr)

	tbl := table.init(&table.Table{})

	for msg in msgs {
		table.row(tbl, padding, msg.symbol, " - ", msg.location)
	}

	table.build(tbl)

	for row in 0..<tbl.nr_rows {
		for col in 0..<tbl.nr_cols {
			table.write_table_cell(w, tbl, row, col)
		}
		io.write_byte(w, '\n')
	}
}
