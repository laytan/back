package elf

import "core:os"
import "core:testing"

import "../dwarf"

@(test)
test_symbols :: proc(t: ^testing.T) {
	fh, err := os.open(os.args[0], os.O_RDONLY)
	testing.expect_value(t, err, 0)
	stream := os.stream_from_handle(fh)

	file: File
	ferr := file_init(&file, stream)
	testing.expect_value(t, ferr, nil)

	sections_err: Error
	idx: int
	for shdr in iter_section_headers(&file, &idx, &sections_err) {
		name, nameerr := section_name(&file, idx-1)
		testing.expect_value(t, nameerr, nil)
		testing.logf(t, "Section: %s, of type %v", name, shdr.type)

		#partial switch shdr.type {
		case .SYMTAB, .DYNSYM, .SUNW_LDYNSYM:
			strtbl: String_Table
			strtbl.file = &file

			strtaberr: Error
			strtbl.hdr, strtaberr = get_section_header(&file, int(shdr.link))
			testing.expect_value(t, strtaberr, nil)

			symtab: Symbol_Table
			symtab.str_table = strtbl
			symtab.hdr = shdr

			assert(symtab.hdr.entsize > 0)
			assert(symtab.hdr.size % symtab.hdr.entsize == 0)

			testing.logf(t, "Symbol table with %v symbols", num_symbols(&symtab))

			sidx: int
			itererr: Error
			for sym in iter_symbols(&symtab, &sidx, &itererr) {
				sname, snameerr := get_string(&symtab.str_table, int(sym.name), context.temp_allocator)
				testing.expect_value(t, snameerr, nil)
				testing.log(t, sname)
			}
			testing.expect_value(t, itererr, nil)
		}
	}
}

@(test)
test_dwarf :: proc(t: ^testing.T) {
	address := uintptr(rawptr(os.open))

	fh, err := os.open(os.args[0], os.O_RDONLY)
	testing.expect_value(t, err, 0)
	stream := os.stream_from_handle(fh)

	file: File
	ferr := file_init(&file, stream)
	testing.expect_value(t, ferr, nil)

	has_dwarf, has_dwarf_err := has_dwarf_info(&file)
	testing.expect_value(t, has_dwarf_err, nil)

	if !has_dwarf {
		testing.log(t, "no dwarf info, skipping their tests")
		return
	}

	info, info_err := dwarf_info(&file, false, false)
	testing.expect_value(t, info_err, nil)

	testing.logf(t, "%#v", info)

	off: u64
	derr: dwarf.Error
	for cu in dwarf.iter_CUs(info, &off, &derr) {
		testing.logf(t, "CU: %#v", cu)

		top, top_err := dwarf.top_DIE(info, cu)
		testing.expect_value(t, top_err, nil)

		testing.logf(t, "Top DIE: %#v", top)

		lp, lp_err := dwarf.line_program_for_CU(info, cu, context.temp_allocator)
		testing.expect_value(t, lp_err, nil)

		testing.logf(t, "Line Program: %#v", lp)

		if rlp, has_lp := lp.?; has_lp {
			entries, decode_err := dwarf.decode_line_program(info, cu, &rlp, context.temp_allocator)
			testing.expect_value(t, decode_err, nil)

			testing.logf(t, "Line Program Entries: %v", len(entries))

			testing.logf(t, "Looking for: %i", address)

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
							testing.logf(t, "Found it %s(%i:%i)", file.name, line, col)
						} else {
							directory := rlp.hdr.include_directories[file.dir_index - 1]
							testing.logf(t, "Found it: %s/%s(%i:%i)", directory, file.name, line, col)
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
	testing.expect_value(t, derr, nil)
}
