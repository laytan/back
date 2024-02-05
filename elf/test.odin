package elf

import "core:os"
import "core:testing"
import "core:sys/llvm"

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

@(test)
test_cfi :: proc(t: ^testing.T) {
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

	testing.logf(t, "test_cfi: %s, %v", symbolize(&file, u64(uintptr(rawptr(test_cfi)))))

	info, info_err := dwarf_info(&file, false, false)
	testing.expect_value(t, info_err, nil)

	regs: dwarf.Registers
	dwarf.registers_current(&regs)

	testing.logf(t, "%#v", regs)

	u: dwarf.Unwinder
	dwarf.unwinder_init(&u, &info, regs)

	cf, u_err := dwarf.unwinder_next(&u)
	testing.expect_value(t, u_err, nil)

	testing.logf(t, "%#v", cf)

	testing.logf(t, "symbol: %v, %v", symbolize(&file, cf.pc))

	cf, u_err = dwarf.unwinder_next(&u)
	testing.expect_value(t, u_err, nil)

	testing.logf(t, "%#v", cf)

	testing.logf(t, "symbol: %v, %v", symbolize(&file, cf.pc))
	//
	// cf, u_err = dwarf.unwinder_next(&u)
	// testing.expect_value(t, u_err, nil)
	//
	// testing.logf(t, "%#v", cf)
	//
	// testing.logf(t, "symbol: %v, %v", symbolize(&file, cf.pc))

	// row, uw_err := dwarf.unwind_info_for_address(&info, address)
	// testing.expect_value(t, uw_err, nil)
	//
	// testing.logf(t, "%#v", row)

	// row, row_err := dwarf.unwind_table_next_row(&tbl)
	// testing.expect_value(t, row_err, nil)
	//
	// testing.logf(t, "%#v", row)
	//
	// row, row_err = dwarf.unwind_table_next_row(&tbl)
	// testing.expect_value(t, row_err, nil)
	//
	// testing.logf(t, "%#v", row)
	//
	// row, row_err = dwarf.unwind_table_next_row(&tbl)
	// testing.expect_value(t, row_err, nil)
	//
	// testing.logf(t, "%#v", row)
	//
	// row, row_err = dwarf.unwind_table_next_row(&tbl)
	// testing.expect_value(t, row_err, nil)
	//
	// testing.logf(t, "%#v", row)
	//
	// row, row_err = dwarf.unwind_table_next_row(&tbl)
	// testing.expect_value(t, row_err, nil)
	//
	// testing.logf(t, "%#v", row)
	//
	// row, row_err = dwarf.unwind_table_next_row(&tbl)
	// testing.expect_value(t, row_err, nil)
	//
	// testing.logf(t, "%#v", row)

	// testing.logf(t, "%#v", ctx)
	// testing.logf(t, "%#v", tbl)

	// entries, cfi_err := dwarf.call_frame_info(info, context.temp_allocator)
	// testing.expect_value(t, cfi_err, nil)
	//
	// testing.logf(t, "Looking for: %i", u64(address))
	//
	// for entry in entries {
	// 	switch et in entry {
	// 	case dwarf.CIE:
	// 		testing.logf(t, "CIE: %#v\n", et)
	// 	case dwarf.FDE:
	// 		start := u64(et.initial_location)
	// 		end   := start + u64(et.address_range)
	//
	// 		if start <= address && address <= end {
	// 			testing.logf(t, "FDE: %#v\n", et)
	// 		}
	//
	// 	case dwarf.Zero:
	// 		testing.log(t, "Zero")
	// 	}
	// }

	// regs: dwarf.Registers
	// dwarf.registers_current(&regs)

	// testing.logf(t, "%#v\n", regs)
}

import "core:slice"
import "core:fmt"

symbolize :: proc(file: ^File, address: u64) -> (symbol_str: string, ok: bool) {
	Entry :: struct {
		table: u32,
		name:  u32,
		value: uintptr,
		size:  uintptr,
	}

	tables  := make([dynamic]Symbol_Table, context.temp_allocator)
	symbols := make([dynamic]Entry,        context.temp_allocator)

	eerr: Error
	idx: int
	for hdr in iter_section_headers(file, &idx, &eerr) {
		#partial switch hdr.type {
		case .SYMTAB, .DYNSYM, .SUNW_LDYNSYM:
			strtbl: String_Table
			strtbl.file = file

			strtbl.hdr, eerr = get_section_header(file, int(hdr.link))
			assert(eerr == nil)

			symtab: Symbol_Table
			symtab.str_table = strtbl
			symtab.hdr = hdr

			assert(symtab.hdr.entsize > 0)
			assert(symtab.hdr.size % symtab.hdr.entsize == 0)

			append(&tables, symtab)
			table := len(tables)-1

			idx: int
			for sym in iter_symbols(&symtab, &idx, &eerr) {
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

	// TODO: this API is weird as fuck.
	i, _ := slice.binary_search_by(symbols[:], Entry{value = uintptr(address)}, proc(a, b: Entry) -> slice.Ordering {
		return slice.cmp_proc(uintptr)(a.value, b.value)
	})

	if i <= 0 {
		return
	}

	symbol := symbols[i]
	offset := uintptr(address) - symbol.value
	if uintptr(address) > symbol.value + symbol.size {
		return
	}

	tbl := tables[symbol.table]

	// TODO: make this one allocation.

	symbol_str, eerr = get_string(&tbl.str_table, int(symbol.name), context.temp_allocator)
	symbol_str = fmt.aprintf("%v +%v", symbol_str, offset)
	assert(eerr == nil)

	ok = true
	return
}
