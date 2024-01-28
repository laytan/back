//+private file
package back

import "core:c"
import "core:fmt"
import "core:os"
import "core:runtime"
import "core:slice"
import "core:sys/linux"
import "core:strings"

import "elf"
import "dwarf"

foreign import lib "system:c"

PROGRAM: string

@(init)
program_init :: proc() {
	// TODO: don't do this in init, handle bigger paths.
	prog: [1024]byte
	read, err := linux.readlink("/proc/self/exe", prog[:])
	assert(read != 1024 && err == .NONE, "reading /proc/self/exe failed")
	PROGRAM = strings.clone_from(prog[:read])
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
		if msg.location != "??" do delete(msg.location)
		if msg.symbol   != "??" do delete(msg.symbol)
	}
	delete(msgs)
}

@(private="package")
_lines :: proc(bt: Trace) -> (out: []Line, err: Lines_Error) {
	out = make([]Line, len(bt))

	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD(ignore=context.allocator==context.temp_allocator)

	fh, errno := os.open(PROGRAM, os.O_RDONLY)
	assert(errno == os.ERROR_NONE)
	defer os.close(fh)

	file: elf.File
	eerr := elf.file_init(&file, os.stream_from_handle(fh))
	assert(eerr == nil)

	Entry :: struct {
		table: u32,
		name:  u32,
		value: uintptr,
		size:  uintptr,
	}

	tables  := make([dynamic]elf.Symbol_Table, context.temp_allocator)
	symbols := make([dynamic]Entry,            context.temp_allocator)

	idx: int
	for hdr in elf.iter_section_headers(&file, &idx, &eerr) {
		#partial switch hdr.type {
		case .SYMTAB, .DYNSYM, .SUNW_LDYNSYM:
			strtbl: elf.String_Table
			strtbl.file = &file

			strtbl.hdr, eerr = elf.get_section_header(&file, int(hdr.link))
			assert(eerr == nil)

			symtab: elf.Symbol_Table
			symtab.str_table = strtbl
			symtab.hdr = hdr

			assert(symtab.hdr.entsize > 0)
			assert(symtab.hdr.size % symtab.hdr.entsize == 0)

			append(&tables, symtab)
			table := len(tables)-1

			idx: int
			for sym in elf.iter_symbols(&symtab, &idx, &eerr) {
				append(&symbols, Entry{
					table = u32(table),
					name  = sym.name,
					value = uintptr(sym.value),
					size  = uintptr(sym.size),
				})
			}
		}
	}
	assert(eerr == nil)

	slice.sort_by(symbols[:], proc(a, b: Entry) -> bool {
		return a.value < b.value
	})

	for &line, i in out {
		// TODO: this API is weird as fuck.
		idx, _ := slice.binary_search_by(symbols[:], Entry{value = uintptr(bt[i])}, proc(a, b: Entry) -> slice.Ordering {
			return slice.cmp_proc(uintptr)(a.value, b.value)
		})

		line = Line {
			location = "??",
			symbol   = "??",
		}

		if idx <= 0 {
			continue
		}

		symbol := symbols[idx-1]
		offset := uintptr(bt[i]) - symbol.value
		if uintptr(bt[i]) > symbol.value + symbol.size {
			continue
		}

		tbl := tables[symbol.table]

		// TODO: make this one allocation.
		line.symbol, eerr = elf.get_string(&tbl.str_table, int(symbol.name), context.temp_allocator)
		line.symbol = fmt.aprintf("%v +%v", line.symbol, offset)

		assert(eerr == nil)
	}

	if has_dwarf, err := elf.has_dwarf_info(&file); !has_dwarf || err != nil {
		return
	}

	info: dwarf.Info
	info, eerr = elf.dwarf_info(&file, false, false)
	assert(eerr == nil)

	off: u64
	derr: dwarf.Error
	for cu in dwarf.iter_CUs(info, &off, &derr) {
		lp, lp_err := dwarf.line_program_for_CU(info, cu, context.temp_allocator)
		assert(lp_err == nil)

		if rlp, has_lp := lp.?; has_lp {
			entries, decode_err := dwarf.decode_line_program(info, cu, &rlp, context.temp_allocator)
			assert(decode_err == nil)

			for _address, i in bt {
				address := uintptr(_address)
				_prev_state: Maybe(dwarf.Line_State)
				for entry in entries {
					state, has_state := entry.state.?
					if !has_state {
						continue
					}

					if prev_state, has_prev_state := _prev_state.?; has_prev_state {
						if uintptr(prev_state.address) <= address && address < uintptr(state.address) {
							file := rlp.hdr.file_entries[prev_state.file - 1]
							line := prev_state.line
							col  := prev_state.column
							if file.dir_index == 0 {
								out[i].location = fmt.aprintf("%s(%i:%i)", file.name, line, col)
							} else {
								directory := rlp.hdr.include_directories[file.dir_index - 1]
								out[i].location = fmt.aprintf("%s/%s(%i:%i)", directory, file.name, line, col)
							}
							break
						}
					}

					if state.end_sequence {
						_prev_state = nil
					} else {
						_prev_state = state
					}
				}
			}
		}
	}

	return
}


foreign lib {
	backtrace :: proc(buffer: [^]rawptr, size: c.int) -> c.int ---
// 	backtrace_symbols :: proc(buffer: [^]rawptr, size: c.int) -> [^]cstring ---
// 	backtrace_symbols_fd :: proc(buffer: [^]rawptr, size: c.int, fd: ^libc.FILE) ---
//
// 	popen :: proc(command: cstring, type: cstring) -> ^libc.FILE ---
// 	pclose :: proc(stream: ^libc.FILE) -> c.int ---
}
//
// // Build command like: `{addr2line_path} {addresses} --functions --exe={program}`.
// make_symbolizer_cmd :: proc(msgs: []cstring) -> (cmd: cstring, err: Lines_Error) {
// 	cmd_builder := strings.builder_make()
//
// 	strings.write_string(&cmd_builder, ADDR2LINE_PATH)
//
// 	for msg in msgs {
// 		addr := parse_address(msg) or_return
//
// 		strings.write_byte(&cmd_builder, ' ')
// 		strings.write_string(&cmd_builder, addr)
// 	}
//
// 	strings.write_string(&cmd_builder, " --functions --exe=")
// 	strings.write_string(&cmd_builder, PROGRAM)
//
// 	strings.write_byte(&cmd_builder, 0)
// 	return strings.unsafe_string_to_cstring(strings.to_string(cmd_builder)), nil
// }
//
// read_message :: proc(buf: []byte, fp: ^libc.FILE) -> (msg: Line, err: Lines_Error) {
// 	msg.symbol   = get_line(buf[:], fp) or_return
// 	msg.location = get_line(buf[:], fp) or_return
// 	return
// }
//
// get_line :: proc(buf: []byte, fp: ^libc.FILE) -> (string, Lines_Error) {
// 	defer slice.zero(buf)
//
// 	got := libc.fgets(raw_data(buf), i32(len(buf)), fp)
// 	if got == nil {
// 		if libc.feof(fp) == 0 {
// 			return "", .Addr2line_Unexpected_EOF
// 		}
// 		return "", .Addr2line_Output_Error
// 	}
//
// 	cout := cstring(raw_data(buf))
// 	if (buf[0] == '?' || buf[0] == ' ') && (buf[1] == '?' || buf[1] == ' ') {
// 		return "??", nil
// 	}
//
// 	ret := strings.clone_from(cout)
// 	ret = strings.trim_right_space(ret)
// 	return ret, nil
// }
//
// // Parses the address out of a backtrace line.
// // Example: .../main() [0x100000] -> 0x100000
// parse_address :: proc(msg: cstring) -> (string, Lines_Error) {
// 	multi := transmute([^]byte)msg
// 	msg_len := len(msg)
// 	#reverse for c, i in multi[:msg_len] {
// 		if c == '[' {
// 			return string(multi[i + 1:msg_len - 1]), nil
// 		}
// 	}
// 	return "", .Parse_Address_Fail
// }
//
