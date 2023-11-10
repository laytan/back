//+private
package obacktracing

import "core:c/libc"
import "core:slice"
import "core:strings"

ADDR2LINE_PATH := #config(TRACE_ADDR2LINE_PATH, "addr2line")

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

