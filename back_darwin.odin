//+private file
package back

import "core:c"
import "core:c/libc"
import "core:fmt"
import "core:os"
import "core:strings"

foreign import lib "system:System.framework"

ATOS_PATH := #config(BACK_ADDR2LINE_PATH, "atos")
PROGRAM   := #config(BACK_PROGRAM, "")

@(init)
program_init :: proc() {
	if PROGRAM == "" do PROGRAM = os.args[0]
}

@(private="package")
_Trace_Entry :: rawptr

@(private="package")
_trace :: proc(buf: Trace) -> (n: int) {
	ctx:    unw_context_t
	cursor: unw_cursor_t

	assert(unw_getcontext(&ctx) == 0)
	assert(unw_init_local(&cursor, &ctx) == 0)

	pc: uintptr
	for ; unw_step(&cursor) > 0 && n < len(buf); n += 1 {
		assert(unw_get_reg(&cursor, .IP, &pc) == 0)
		buf[n] = rawptr(pc)
	}

	return
}

@(private="package")
_lines_destroy :: proc(lines: []Line) {
	for line in lines {
		delete(line.location)
		delete(line.symbol)
	}
	delete(lines)
}

@(private="package")
_lines :: proc(bt: Trace) -> (out: []Line, err: Lines_Error) {
	out = make([]Line, len(bt))

	when ODIN_DEBUG {
		cmd := make_symbolizer_cmd(bt) or_return
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
		for &msg in out {
			msg = read_message(line_buf[:], fp) or_return
			line_buf = 0
		}
		return
	} else {
		info: Dl_info
		for frame, i in bt {
			assert(dladdr(frame, &info) != 0)

			msg := &out[i]
			msg.location = strings.clone_from(info.fname)
			msg.symbol   = strings.clone_from(info.sname)
		}
		return
	}
}

// These could actually be smaller, but then we would have to define and check the size on each
// architecture, the sizes here are the largest they can be.
_LIBUNWIND_CONTEXT_SIZE :: 167
_LIBUNWIND_CURSOR_SIZE :: 204

unw_context_t :: struct {
	data: [_LIBUNWIND_CONTEXT_SIZE]u64,
}

unw_cursor_t :: struct {
	data: [_LIBUNWIND_CURSOR_SIZE]u64,
}

// Cross-platform registers, each architecture has additional registers but these are enough for us.
Register :: enum i32 {
	SP = -2,
	IP = -1,
}

Dl_info :: struct {
	fname: cstring, /* Pathname of shared object */
	fbase: rawptr, /* Base address of shared object */
	sname: cstring, /* Name of nearest symbol */
	saddr: rawptr, /* Address of nearest symbol */
}

segment_command_t :: struct {
	cmd:      c.uint, /* LC_SEGMENT_64 */
	cmdsize:  c.uint, /* includes sizeof section_64 structs */
	segname:  [16]u8, /* segment name */
	vmaddr:   c.ulong, /* memory address of this segment */
	vmsize:   c.ulong, /* memory size of this segment */
	fileoff:  c.ulong, /* file offset of this segment */
	filesize: c.ulong, /* amount to map from the file */
	maxprot:  c.int, /* maximum VM protection */
	initprot: c.int, /* initial VM protection */
	nsects:   c.uint, /* number of sections in segment */
	flags:    c.uint, /* flags */
}

foreign lib {
	unw_getcontext :: proc(ctx: ^unw_context_t) -> i32 ---
	unw_init_local :: proc(cursor: ^unw_cursor_t, ctx: ^unw_context_t) -> i32 ---
	unw_get_reg :: proc(cursor: ^unw_cursor_t, name: Register, reg: ^uintptr) -> i32 ---
	unw_step :: proc(cursor: ^unw_cursor_t) -> i32 ---

	popen :: proc(command: cstring, type: cstring) -> ^libc.FILE ---
	pclose :: proc(stream: ^libc.FILE) -> i32 ---

	dladdr :: proc(addr: rawptr, dl_info: ^Dl_info) -> i32 ---

	getsegbyname :: proc(name: cstring) -> ^segment_command_t ---
	_dyld_image_count :: proc() -> c.uint ---
	_dyld_get_image_name :: proc(i: c.uint) -> cstring ---
	_dyld_get_image_vmaddr_slide :: proc(i: c.uint) -> uintptr ---
}

// Constructs the `atos` command to be executed.
make_symbolizer_cmd :: proc(bt: Trace) -> (cmd: cstring, err: Lines_Error) {
	addr, ok := load_addr()
	if !ok do return "", .Parse_Address_Fail

	cmd_builder := strings.builder_make()

	strings.write_string(&cmd_builder, ATOS_PATH)
	strings.write_byte(&cmd_builder, ' ')

	strings.write_string(&cmd_builder, "-o ")
	strings.write_string(&cmd_builder, PROGRAM)

	strings.write_string(&cmd_builder, " -l ")
	fmt.sbprintf(&cmd_builder, "%v ", rawptr(addr))

	strings.write_string(&cmd_builder, "-fullPath")

	for addr in bt {
		fmt.sbprintf(&cmd_builder, " %v", addr)
	}

	strings.write_byte(&cmd_builder, 0)
	return strings.unsafe_string_to_cstring(strings.to_string(cmd_builder)), nil
}

// Parses a single message out of the command output.
read_message :: proc(buf: []byte, fp: ^libc.FILE) -> (msg: Line, err: Lines_Error) {
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
		msg.symbol   = strings.clone("??")
		msg.location = strings.clone("??")
		return
	}

	msg.symbol   = strings.clone(strings.trim_right_space(cout[:symbol_end]))
	msg.location = strings.clone(cout[loc_start + 1:len(cout) - 2])
	return
}

// Loads the offset at which the addresses returned from `backtrace` are.
// The `atos` command needs this information.
load_addr :: proc() -> (uintptr, bool) {
	@(static)
	_addr: uintptr
	if _addr != 0 {
		return _addr, true
	}

	cmd := getsegbyname("__TEXT")
	if cmd == nil do return 0, false

	for i in 0 ..< _dyld_image_count() {
		name := _dyld_get_image_name(i)
		if name == nil do continue
		if string(name) != PROGRAM do continue

		ok: bool
		_addr, ok = uintptr(cmd.vmaddr) + _dyld_get_image_vmaddr_slide(i), true
		return _addr, ok
	}

	return 0, false
}
