//+build linux, darwin
//+private
package obacktracing

import "core:c"
import "core:c/libc"
import "core:os"
import "core:path/filepath"
import "core:strings"

when ODIN_OS == .Darwin {
	foreign import libc_ "system:System.framework"
} else {
	foreign import libc_ "system:c"
}

PROGRAM := #config(TRACE_PROGRAM, "")

@(init, private)
config_set_defaults :: proc() {
	if PROGRAM == "" do PROGRAM = os.args[0]

	if !filepath.is_abs(PROGRAM) {
		ok: bool
		PROGRAM, ok = filepath.abs(PROGRAM)
		assert(ok, "could not convert program path to an absolute one")
	}
}

foreign libc_ {
	backtrace :: proc(buffer: [^]rawptr, size: c.int) -> c.int ---
	backtrace_symbols :: proc(buffer: [^]rawptr, size: c.int) -> [^]cstring ---
	backtrace_symbols_fd :: proc(buffer: [^]rawptr, size: c.int, fd: ^libc.FILE) ---

	@(private)
	popen :: proc(command: cstring, type: cstring) -> ^libc.FILE ---
	@(private)
	pclose :: proc(stream: ^libc.FILE) -> c.int ---
}

_Backtrace :: []rawptr

_backtrace_get :: proc(max_len: i32, allocator := context.allocator) -> Backtrace {
	trace := make(Backtrace, max_len, allocator)
	size := backtrace(raw_data(trace), max_len)
	return trace[:size]
}

_backtrace_delete :: proc(bt: Backtrace) {
	delete(bt)
}

_backtrace_messages :: proc(bt: Backtrace, allocator := context.allocator) -> (out: []Message, err: Message_Error) {
	context.allocator = allocator

	msgs := backtrace_symbols(raw_data(bt), i32(len(bt)))[:len(bt)]
	defer libc.free(raw_data(msgs))

	out = make([]Message, len(bt))

	// Debug info is needed.
	when !ODIN_DEBUG {
		for msg, i in msgs {
			out[i] = Message {
				location = strings.clone_from(msg),
				symbol   = "??",
			}
		}
		return
	}

	// TODO: check if addr2line is executable.
	// check_symbolizer()

	cmd := make_symbolizer_cmd(msgs) or_return
	defer delete(cmd)

	fp := popen(cmd, "r")
	if fp == nil {
		err = Message_Error(libc.errno()^)
		return
	}
	defer pclose(fp)

	// Parse output, each address gets 2 lines of output,
	// one for the function/symbol and one for the location.
	// If it could not be resolved, '??' is put out.
	line_buf: [1024]byte
	for msg, i in msgs {
		out[i] = read_message(line_buf[:], fp) or_return
		if out[i].location == "" || out[i].location == "??" {
			out[i].location = strings.clone_from(msg)
		}

		line_buf = 0
	}

	return
}
