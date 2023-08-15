package obacktracing

import "core:c"
import "core:c/libc"
import "core:fmt"
import "core:os"
import "core:runtime"
import "core:slice"
import "core:strings"

when ODIN_OS == .Windows {
    #panic("obacktracing does not support Windows")
} else when ODIN_OS == .Darwin {
	foreign import libc_ "system:System.framework"
} else {
	foreign import libc_ "system:c"
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

Backtrace :: []rawptr

backtrace_get :: proc(max_len: i32, allocator := context.allocator) -> Backtrace {
	trace := make(Backtrace, max_len, allocator)
	size := backtrace(raw_data(trace), max_len)
	return trace[:size]
}

backtrace_delete :: proc(b: Backtrace) {
	delete(b)
}

Message :: struct {
	location: string,
	symbol:   string,
}

messages_delete :: proc(msgs: []Message) {
	for msg in msgs do message_delete(msg)
	delete(msgs)
}

message_delete :: proc(m: Message) {
	delete(m.location)

	// There is no symbol info outside of debug mode.
	when ODIN_DEBUG do delete(m.symbol)
}

Message_Error :: enum {
	None,
	Parse_Address_Fail,
	Addr2line_Unexpected_EOF,
	Addr2line_Output_Error,
	Addr2line_Unresolved,
	Fork_Limited = int(os.EAGAIN),
	Out_Of_Memory = int(os.ENOMEM),
	Invalid_Fd = int(os.EFAULT),
	Pipe_Process_Limited = int(os.EMFILE),
	Pipe_System_Limited = int(os.ENFILE),
	Fork_Not_Supported = int(os.ENOSYS),
}

// Processes the message trying to get more/useful information.
// This adds file and line information if the program is running in debug mode.
//
// The `program` arg should be the file path of the executable.
// You can leave this nil and it will default to os.args[0].
//
// If an error is returned the original message will be the result and is save to use.
backtrace_messages :: proc(
	bt: Backtrace,
	program: Maybe(string) = nil,
	addr2line_path: string = "addr2line",
	allocator := context.allocator,
) -> (
	out: []Message,
	err: Message_Error,
) {
	context.allocator = allocator

	msgs := backtrace_symbols(raw_data(bt), i32(len(bt)))[:len(bt)]
	defer libc.free(raw_data(msgs))

	out = make([]Message, len(bt))

	// Cop out of using addr2line when we know it won't work.
	// Debug info is needed and only linux has the `addr2line` util.
	when !ODIN_DEBUG || ODIN_OS != .Linux {
		for msg, i in msgs {
			out[i] = Message {
				location = strings.clone_from(msg),
				symbol   = "??",
			}
		}
		return
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

	// Retrieves a line of output as an allocated string without the line break.
	// buf is intended to be the same over multiple calls, and is zero'd at the end for reuse.
	get_line :: proc(buf: []byte, fp: ^libc.FILE, default: cstring) -> (string, Message_Error) {
		defer slice.zero(buf)

		got := libc.fgets(raw_data(buf), c.int(len(buf)), fp)
		if got == nil {
			if libc.feof(fp) == 0 {
				return "", .Addr2line_Unexpected_EOF
			}
			return "", .Addr2line_Output_Error
		}

		cout := cstring(raw_data(buf))
		if buf[0] == '?' && buf[1] == '?' {
			cout = default
		}

		ret := strings.clone_from(cout)
		ret = strings.trim_right_space(ret)
		return ret, nil
	}

	// Build command like: `{addr2line_path} {addresses} --functions --exe={program}`.
	cmd_builder := strings.builder_make()
	defer strings.builder_destroy(&cmd_builder)
	strings.write_string(&cmd_builder, addr2line_path)
	for msg in msgs {
		addr := parse_address(msg) or_return

		strings.write_byte(&cmd_builder, ' ')
		strings.write_string(&cmd_builder, addr)
	}
	strings.write_string(&cmd_builder, " --functions --exe=")
	strings.write_string(&cmd_builder, program.? or_else os.args[0])
	strings.write_byte(&cmd_builder, 0)
	cmd_ := strings.to_string(cmd_builder)
	cmd := cstring(raw_data(cmd_))

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
		out[i] = Message {
			symbol   = get_line(line_buf[:], fp, "??") or_return,
			location = get_line(line_buf[:], fp, msg) or_return,
		}
	}

	return
}

assertion_failure_proc :: proc(prefix, message: string, loc: runtime.Source_Code_Location) -> ! {
    t := backtrace_get(17)
    msgs, err := backtrace_messages(t)
    if err != nil {
        fmt.printf("could not get backtrace for assertion failure: %v\n", err)
        runtime.default_assertion_failure_proc(prefix, message, loc)
    } else {
        fmt.println("[back trace]")
		for msg in msgs[min(1, len(msgs)-1):] {
			fmt.printf("    %s - %s\n", msg.symbol, msg.location)
		}

        runtime.default_assertion_failure_proc(prefix, message, loc)
    }
}
