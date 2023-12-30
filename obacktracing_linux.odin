//+private file
package obacktracing

import "core:c"
import "core:c/libc"
import "core:os"
import "core:slice"
import "core:strings"

foreign import lib "system:c"

ADDR2LINE_PATH := #config(TRACE_ADDR2LINE_PATH, "addr2line")
PROGRAM        := #config(TRACE_PROGRAM, "")

@(init)
config_set_defaults :: proc() {
	if PROGRAM == "" do PROGRAM = os.args[0]
}

@(private="package")
_Backtrace :: []rawptr

@(private="package")
_backtrace_get :: proc(max_len: i32, allocator := context.allocator) -> Backtrace {
	trace := make(Backtrace, max_len, allocator)
	size := backtrace(raw_data(trace), max_len)
	return trace[:size]
}

@(private="package")
_backtrace_delete :: proc(bt: Backtrace, allocator := context.allocator) {
	delete(bt, allocator)
}

@(private="package")
_messages_delete :: proc(msgs: []Message, allocator := context.allocator) {
	context.allocator = allocator

	for msg in msgs {
		delete(msg.location)

		when ODIN_DEBUG {
			if msg.symbol != "" && msg.symbol != "??" do delete(msg.symbol)
		}
	}
	delete(msgs)
}

@(private="package")
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


foreign lib {
	backtrace :: proc(buffer: [^]rawptr, size: c.int) -> c.int ---
	backtrace_symbols :: proc(buffer: [^]rawptr, size: c.int) -> [^]cstring ---
	backtrace_symbols_fd :: proc(buffer: [^]rawptr, size: c.int, fd: ^libc.FILE) ---

	popen :: proc(command: cstring, type: cstring) -> ^libc.FILE ---
	pclose :: proc(stream: ^libc.FILE) -> c.int ---
}

// Build command like: `{addr2line_path} {addresses} --functions --exe={program}`.
make_symbolizer_cmd :: proc(msgs: []cstring) -> (cmd: cstring, err: Message_Error) {
	cmd_builder := strings.builder_make()

	strings.write_string(&cmd_builder, ADDR2LINE_PATH)

	for msg in msgs {
		addr := parse_address(msg) or_return

		strings.write_byte(&cmd_builder, ' ')
		strings.write_string(&cmd_builder, addr)
	}

	strings.write_string(&cmd_builder, " --functions --exe=")
	strings.write_string(&cmd_builder, PROGRAM)

	strings.write_byte(&cmd_builder, 0)
	return strings.unsafe_string_to_cstring(strings.to_string(cmd_builder)), nil
}

read_message :: proc(buf: []byte, fp: ^libc.FILE) -> (msg: Message, err: Message_Error) {
	msg.symbol   = get_line(buf[:], fp) or_return
	msg.location = get_line(buf[:], fp) or_return
	return
}

get_line :: proc(buf: []byte, fp: ^libc.FILE) -> (string, Message_Error) {
	defer slice.zero(buf)

	got := libc.fgets(raw_data(buf), i32(len(buf)), fp)
	if got == nil {
		if libc.feof(fp) == 0 {
			return "", .Addr2line_Unexpected_EOF
		}
		return "", .Addr2line_Output_Error
	}

	cout := cstring(raw_data(buf))
	if (buf[0] == '?' || buf[0] == ' ') && (buf[1] == '?' || buf[1] == ' ') {
		return "??", nil
	}

	ret := strings.clone_from(cout)
	ret = strings.trim_right_space(ret)
	return ret, nil
}

// Parses the address out of a backtrace line.
// Example: .../main() [0x100000] -> 0x100000
parse_address :: proc(msg: cstring) -> (string, Message_Error) {
	multi := transmute([^]byte)msg
	msg_len := len(msg)
	#reverse for c, i in multi[:msg_len] {
		if c == '[' {
			return string(multi[i + 1:msg_len - 1]), nil
		}
	}
	return "", .Parse_Address_Fail
}

