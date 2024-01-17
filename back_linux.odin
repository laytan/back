//+private file
package back

import "core:c"
import "core:c/libc"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:slice"
import "core:strings"

foreign import lib "system:c"

ADDR2LINE_PATH := #config(TRACE_ADDR2LINE_PATH, "addr2line")
PROGRAM        := #config(BACK_PROGRAM, "")

@(init)
program_init :: proc() {
	if PROGRAM == "" {
		PROGRAM = os.args[0]
		if !filepath.is_abs(PROGRAM) {
			if abs, ok := filepath.abs(PROGRAM); ok {
				PROGRAM = abs
			} else {
				fmt.eprintln("back: could not convert `os.args[0]` to an absolute path")
			}
		}
	}
}

@(private="package")
_Trace_Entry :: rawptr

@(private="package")
_trace :: proc(buf: Trace) -> (n: int) {
	n = int(backtrace(raw_data(buf), i32(len(buf))))
	return
}

@(private="package")
_lines_destroy :: proc(msgs: []Line) {
	for msg in msgs {
		delete(msg.location)

		when ODIN_DEBUG {
			if msg.symbol != "" && msg.symbol != "??" do delete(msg.symbol)
		}
	}
	delete(msgs)
}

@(private="package")
_lines :: proc(bt: Trace) -> (out: []Line, err: Lines_Error) {
	msgs := backtrace_symbols(raw_data(bt), i32(len(bt)))[:len(bt)]
	defer libc.free(raw_data(msgs))

	out = make([]Line, len(bt))

	// Debug info is needed.
	when !ODIN_DEBUG {
		for msg, i in msgs {
			out[i] = Line {
				location = strings.clone_from(msg),
				symbol   = "??",
			}
		}
		return
	}

	cmd := make_symbolizer_cmd(msgs) or_return
	defer delete(cmd)

	fp := popen(cmd, "r")
	if fp == nil {
		err = Lines_Error(libc.errno()^)
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
make_symbolizer_cmd :: proc(msgs: []cstring) -> (cmd: cstring, err: Lines_Error) {
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

read_message :: proc(buf: []byte, fp: ^libc.FILE) -> (msg: Line, err: Lines_Error) {
	msg.symbol   = get_line(buf[:], fp) or_return
	msg.location = get_line(buf[:], fp) or_return
	return
}

get_line :: proc(buf: []byte, fp: ^libc.FILE) -> (string, Lines_Error) {
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
parse_address :: proc(msg: cstring) -> (string, Lines_Error) {
	multi := transmute([^]byte)msg
	msg_len := len(msg)
	#reverse for c, i in multi[:msg_len] {
		if c == '[' {
			return string(multi[i + 1:msg_len - 1]), nil
		}
	}
	return "", .Parse_Address_Fail
}

