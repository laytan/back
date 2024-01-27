package elf

import "core:os"
import "core:testing"
import "core:slice"

@(test)
test_file :: proc(t: ^testing.T) {
	fh, err := os.open(os.args[0], os.O_RDONLY)
	testing.expect_value(t, err, 0)
	stream := os.stream_from_handle(fh)

	file: File
	ferr := file_init(&file, stream)
	testing.expect_value(t, ferr, nil)

	testing.logf(t, "%#v", file)

	symbols: [dynamic]Entry
	Entry :: struct {
		name:  string,
		value: uintptr,
		size:  uintptr,
	}

	sections_err: Error
	idx: int
	for shdr in iter_section_headers(&file, &idx, &sections_err) {
		name, nameerr := section_name(&file, shdr)
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

			// sym, ok, symerr := get_symbol_by_name(&symtab, "elf.test_file")
			// testing.expect_value(t, symerr, nil)
			//
			// if ok {
			// 	testing.logf(t, "\tFound %#v", sym)
			// }

			idx: int
			itererr: Error
			for sym in iter_symbols(&symtab, &idx, &itererr) {
				name, nameerr := get_string(&symtab.str_table, int(sym.name), context.temp_allocator)
				testing.expect_value(t, nameerr, nil)
				append(&symbols, Entry{ name = name, value = uintptr(sym.value), size = uintptr(sym.size) })
			}
			testing.expect_value(t, itererr, nil)
		}
	}
	testing.expect_value(t, sections_err, nil)

	slice.sort_by(symbols[:], proc(a, b: Entry) -> bool {
		return a.value < b.value
	})

	testing.logf(t, "%#v", symbols)
}
