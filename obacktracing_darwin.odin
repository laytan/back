//+private
package obacktracing

import "core:c"
import "core:c/libc"
import "core:fmt"
import "core:strings"

ATOS_PATH :: #config(TRACE_ATOS_PATH, "atos")

DL_Info :: struct {
	dli_fname: cstring,	/* Pathname of shared object */
	dli_fbase: rawptr,	/* Base address of shared object */
	dli_sname: cstring,	/* Name of nearest symbol */
	dli_saddr: rawptr,	/* Address of nearest symbol */
}

segment_command_t :: struct {
	cmd:      c.uint,	/* LC_SEGMENT_64 */
	cmdsize:  c.uint,	/* includes sizeof section_64 structs */
	segname:  [16]u8,	/* segment name */
	vmaddr:   c.ulong,	/* memory address of this segment */
	vmsize:   c.ulong,	/* memory size of this segment */
	fileoff:  c.ulong,	/* file offset of this segment */
	filesize: c.ulong,	/* amount to map from the file */
	maxprot:  c.int,	/* maximum VM protection */
	initprot: c.int,	/* initial VM protection */
	nsects:   c.uint,	/* number of sections in segment */
	flags:    c.uint,	/* flags */
}

foreign {
	getsegbyname                 :: proc(name: cstring) -> ^segment_command_t ---
	_dyld_image_count            :: proc() -> c.uint ---
	_dyld_get_image_name         :: proc(i: c.uint) -> cstring ---
	_dyld_get_image_vmaddr_slide :: proc(i: c.uint) -> uintptr ---
	dladdr                       :: proc(addr: rawptr, dl_info: ^DL_Info) -> c.int ---
}

// Constructs the `atos` command to be executed.
make_symbolizer_cmd :: proc(msgs: []cstring) -> (cmd: cstring, err: Message_Error) {
	addr, ok := load_addr()
	if !ok do return "", .Parse_Address_Fail

	cmd_builder := strings.builder_make()

	strings.write_string(&cmd_builder, ATOS_PATH)
	strings.write_byte(&cmd_builder, ' ')

	strings.write_string(&cmd_builder, "-o ")
	strings.write_string(&cmd_builder, PROGRAM)

	strings.write_string(&cmd_builder, " -arch ")
	strings.write_string(&cmd_builder, "arm64" when ODIN_ARCH == .arm64 else "x86_64")

	strings.write_string(&cmd_builder, " -l ")
	fmt.wprintf(strings.to_writer(&cmd_builder), "%p ", rawptr(addr))

	strings.write_string(&cmd_builder, "-fullPath")

	for msg in msgs {
		addr := parse_address(msg) or_return

		strings.write_byte(&cmd_builder, ' ')
		strings.write_string(&cmd_builder, addr)
	}

	strings.write_byte(&cmd_builder, 0)
	return strings.unsafe_string_to_cstring(strings.to_string(cmd_builder)), nil
}

// Parses a single message out of the command output.
read_message :: proc(buf: []byte, fp: ^libc.FILE) -> (msg: Message, err: Message_Error) {
	got := libc.fgets(raw_data(buf), c.int(len(buf)), fp)
	if got == nil {
		if libc.feof(fp) == 0 {
			err = .Addr2line_Unexpected_EOF
			return
		}

		err = .Addr2line_Output_Error
		return
	}

	cout := string(cstring(raw_data(buf)))
	
	symbol_end := strings.index_byte(cout, '(')
	loc_start  := strings.last_index_byte(cout, '(')

	if symbol_end == -1 || loc_start == -1 || len(cout) < 5 {
		msg.symbol   = "??"
		msg.location = "??"
		return
	}
	
	msg.symbol   = strings.clone(strings.trim_right_space(cout[:symbol_end]))
	msg.location = strings.clone(cout[loc_start+1:len(cout)-2])
	return
}

// Loads the offset at which the addresses returned from `backtrace` are.
// The `atos` command needs this information.
load_addr :: proc() -> (addr: uintptr, ok: bool) {
	cmd := getsegbyname("__TEXT")
	if cmd == nil do return
	
	for i in 0..<_dyld_image_count() {
		name := _dyld_get_image_name(i)
		if name == nil             do continue
		if string(name) != PROGRAM do continue

		return uintptr(cmd.vmaddr) + _dyld_get_image_vmaddr_slide(i), true
	}

	return
}

// Returns the hex address out of the msg, always seems to be the 3rd field.
parse_address :: proc(msg: cstring) -> (string, Message_Error) {
	s := string(msg)
	i: int
	for field in strings.fields_iterator(&s) {
		if i == 2 do return field, nil
		i += 1
	}

	return "", .Parse_Address_Fail
}

