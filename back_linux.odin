#+vet explicit-allocators
#+private file
package back

@require import "base:runtime"

@require import "core:c"
@require import "core:c/libc"
@require import "core:os"
@require import "core:strings"

ADDR2LINE_PATH :: #config(TRACE_ADDR2LINE_PATH, "addr2line")

when !USE_FALLBACK {

foreign import lib "system:c"

@(private="package")
_Trace_Entry :: rawptr

@(private="package")
_trace :: proc(buf: Trace) -> (n: int) {
	n = int(backtrace(raw_data(buf), i32(len(buf))))
	return
}

@(private="package")
_lines_destroy :: proc(msgs: []Line, allocator: runtime.Allocator) {
	for msg in msgs {
		delete(msg.location, allocator)

		when ODIN_DEBUG {
			if msg.symbol != "" && msg.symbol != "??" { delete(msg.symbol, allocator) }
		}
	}
	delete(msgs, allocator)
}

@(private="package")
_lines :: proc(bt: Trace, allocator, temp_allocator: runtime.Allocator) -> (out: []Line, err: Lines_Error) {
	msgs := backtrace_symbols(raw_data(bt), i32(len(bt)))[:len(bt)]
	defer libc.free(raw_data(msgs))

	out = make([]Line, len(bt), allocator)
	defer if err != nil { _lines_destroy(out, allocator) }

	// Debug info is needed.
	when !ODIN_DEBUG {
		for msg, i in msgs {
			location, mem_err := strings.clone_from(msg, allocator)
			if mem_err != nil { return out, .Out_Of_Memory }

			out[i] = Line {
				location = location,
				symbol   = "??",
			}
		}
		return
	}

	i := 0

	command := make([dynamic]string, temp_allocator)
	defer delete(command)

	if _, err := append(&command, ADDR2LINE_PATH, "--functions", "--exe", ""); err != nil { return out, .Out_Of_Memory }

	COMMAND_EXE_POS   :: 3
	COMMAND_START_LEN :: 4

	for msg in msgs {
		exe, addr := parse_address(msg) or_return
		if command[COMMAND_EXE_POS] == "" {
			command[COMMAND_EXE_POS] = exe
		} else if command[COMMAND_EXE_POS] != exe {
			i += exec_and_fill(command[:], out[i:], msgs[i:], allocator, temp_allocator) or_return

			command[COMMAND_EXE_POS] = exe
			resize(&command, COMMAND_START_LEN)
		}

		if _, err := append(&command, addr); err != nil { return out, .Out_Of_Memory }
	}

	if len(command) > COMMAND_START_LEN {
		i += exec_and_fill(command[:], out[i:], msgs[i:], allocator, temp_allocator) or_return
	}

	return

	// Parses the exe and address out of a backtrace line.
	// Example: .../main(+0x20) [0x100000] -> .../main, +0x20, nil
	parse_address :: proc(cmsg: cstring) -> (string, string, Lines_Error) {
		msg := string(cmsg)
		close_idx := strings.last_index_byte(msg, ')')
		if close_idx < 1 {
			return "", "", .Parse_Address_Fail
		}

		open_idx := strings.last_index_byte(msg[:close_idx], '(')
		if open_idx < 0 {
			return "", "", .Parse_Address_Fail
		}

		return msg[:open_idx], msg[open_idx+1:close_idx], nil
	}

	process_line :: proc(line: string, ok: bool, allocator: runtime.Allocator) -> (string, Lines_Error) {
		if !ok { return "", .Addr2line_Unexpected_EOF }
		if line == "" { return "", .Addr2line_Output_Error }

		if len(line) > 1 && (line[0] == '?' || line[0] == ' ') && (line[1] == '?' || line[1] == ' ') {
			return "??", nil
		}

		ret, err := strings.clone(strings.trim_right_space(line), allocator)
		return ret, err == nil ? nil : .Out_Of_Memory
	}

	exec_and_fill :: proc(command: []string, out: []Line, msgs: []cstring, allocator, temp_allocator: runtime.Allocator) -> (filled: int, err: Lines_Error) {
		state, stdout, stderr, perr := os.process_exec({command = command}, temp_allocator)
		defer delete(stdout, temp_allocator)
		defer delete(stderr, temp_allocator)

		if perr != nil || !state.success {
			return 0, .Addr2line_Process_Error
		}

		count := len(command)-COMMAND_START_LEN

		sstdout := string(stdout)
		for i in 0..<count {
			out[i].symbol   = process_line(strings.split_lines_iterator(&sstdout), allocator) or_return
			out[i].location = process_line(strings.split_lines_iterator(&sstdout), allocator) or_return
			if out[i].location == "" || out[i].location == "??" {
				fallback, mem_err := strings.clone_from(msgs[i], allocator)
				if mem_err != nil { return 0, .Out_Of_Memory }
				out[i].location = fallback
			}
		}

		return count, nil
	}
}

foreign lib {
	backtrace :: proc(buffer: [^]rawptr, size: c.int) -> c.int ---
	backtrace_symbols :: proc(buffer: [^]rawptr, size: c.int) -> [^]cstring ---
	backtrace_symbols_fd :: proc(buffer: [^]rawptr, size: c.int, fd: ^libc.FILE) ---
}

}
