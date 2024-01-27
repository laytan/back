package elf

import "core:io"

String_Table :: struct {
	file: ^File,
	hdr:  Shdr,
}

get_string :: proc(tbl: ^String_Table, off: int, allocator := context.allocator) -> (str: string, err: Error) {
	off := i64(tbl.hdr.offset) + i64(off)
	io.seek(tbl.file.reader, i64(off), .Start) or_return

	buf := make([dynamic]byte, allocator) or_return
	for {
		byte := io.read_byte(tbl.file.reader) or_return
		if byte == 0 { break }
		append(&buf, byte) or_return
	}

	str = string(buf[:])
	return
}

Symbol_Table :: struct {
	str_table: String_Table,
	hdr:       Shdr,
}

Symbol :: struct {
	name:  u32,
	value: u64,
	size:  u64,
	info:  byte,    // TODO: bitfield, 4 bits `bind`, 4 bits `type`.
	other: byte,    // TODO: bitfield, 3 bits `local`, 2 bits padding, 3 bits `visibility`.
	shndx: St_SHNDX,
}

St_SHNDX :: enum u16 {
	Undef  = 0,
	Abs    = 0xfff1,
	Common = 0xfff2,
}

num_symbols :: proc(tbl: ^Symbol_Table) -> u64 {
	return tbl.hdr.size / tbl.hdr.entsize
}

get_symbol :: proc(tbl: ^Symbol_Table, n: int) -> (sym: Symbol, err: Error) {
	file := tbl.str_table.file

	entry_offset := i64(tbl.hdr.offset) + i64(n) * i64(tbl.hdr.entsize)
	io.seek(file.reader, entry_offset, .Start) or_return

	switch file.header.ident.class {
	case .Bits_32:
		read_u32 (file, &sym.name)  or_return
		read_uint(file, &sym.value) or_return

		inter: u32
		read_u32(file, &inter) or_return
		sym.size = u64(inter)

		sym.info  = io.read_byte(file.reader) or_return
		sym.other = io.read_byte(file.reader) or_return

		read_u16(file, (^u16)(&sym.shndx)) or_return

	case .Bits_64:
		read_u32(file, &sym.name) or_return

		sym.info  = io.read_byte(file.reader) or_return
		sym.other = io.read_byte(file.reader) or_return

		read_u16(file, (^u16)(&sym.shndx)) or_return

		read_uint(file, &sym.value) or_return
		read_uint(file, &sym.size)  or_return
	case:
		unreachable()
	}

	return
}

get_symbol_by_name :: proc(tbl: ^Symbol_Table, name: string, allocator := context.temp_allocator) -> (res_sym: Symbol, exists: bool, err: Error) {
	idx: int
	for sym in iter_symbols(tbl, &idx, &err) {
		// TODO: make one buffer, use it for all strings in this loop.
		name_str := get_string(&tbl.str_table, int(sym.name), allocator) or_return
		if name_str == name {
			exists  = true
			res_sym = sym
			return
		}
	}
	return
}

iter_symbols :: proc(tbl: ^Symbol_Table, idx: ^int, err: ^Error) -> (sym: Symbol, ok: bool) {
	defer idx^ = idx^ + 1

	if idx^ >= int(num_symbols(tbl)) {
		return {}, false
	}

	errv: Error
	sym, errv = get_symbol(tbl, idx^)
	if errv != nil {
		err^ = errv
		ok   = false
		return
	}

	ok = true
	return
}
