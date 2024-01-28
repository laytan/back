package elf

import "core:io"

Section :: union {
	String_Table,
	Symbol_Table,
	Section_Base,
}

Section_Base :: struct {
	file: ^File,
	hdr:  Shdr,
	name: string,
}

Section_Size :: struct {
	compression_type:   Compression_Type,
	decompressed_size:  u64,
	decompressed_align: u64,
}

Chdr :: struct {
	type:      Compression_Type,
	reserved:  u32,
	size:      u64,
	addralign: u64,
}
CHDR_SIZE_64: i64: size_of(Chdr)
CHDR_SIZE_32: i64: size_of(Chdr) - (3 * size_of(u32))

Compression_Type :: enum u32 {
	NONE   = 0,
	ZLIB   = 1,
	LOOS   = 0x60000000,
	HIOS   = 0x6fffffff,
	LOPROC = 0x70000000,
	HIPROC = 0x7fffffff,
}

section_base :: proc(section: Section) -> Section_Base {
	switch s in section {
	case Section_Base: return s
	case String_Table: return s.base
	case Symbol_Table: return s.base
	case:              unreachable()
	}
}

section_size :: proc(section: Section) -> (size: Section_Size, err: Error) {
	base := section_base(section)
	// TODO: I am guessing here.
	compressed := base.hdr.flags & 0x800 > 0

	if compressed {
		io.seek(base.file.reader, i64(base.hdr.offset), .Start) or_return

		chdr: Chdr
		read_u32(base.file, (^u32)(&chdr.type)) or_return

		if base.file.header.ident.class == .Bits_64 {
			read_u32(base.file, &chdr.reserved) or_return
		}

		read_uint(base.file, &chdr.size)      or_return
		read_uint(base.file, &chdr.addralign) or_return

		size.compression_type   = chdr.type
		size.decompressed_size  = chdr.size
		size.decompressed_align = chdr.addralign
		return
	}

	size.decompressed_size  = base.hdr.size
	size.decompressed_align = base.hdr.addralign
	return
}

// TODO: return a stream, instead of allocating.
//
// Returns an allocated chunk of the file containing the section data.
// If the data is compressed it is first decompressed.
section_data :: proc(section: Section, allocator := context.allocator) -> (data: []byte, err: Error) {
	base := section_base(section)
	sz := section_size(base) or_return
	#partial switch sz.compression_type {
	case .NONE:
		io.seek(base.file.reader, i64(base.hdr.offset), .Start) or_return

		data = make([]byte, sz.decompressed_size, allocator) or_return
		defer { if err != nil { delete(data, allocator) } }

		io.read_full(base.file.reader, data) or_return
		return

	case .ZLIB:
		panic("unimplemented: zlib compressed sections")
		// hdr_size := CHDR_SIZE_64 if base.file.header.ident.class == .Bits_64 else CHDR_SIZE_32
		// off      := i64(base.hdr.offset) + hdr_size
		// io.seek(base.file.reader, off, .Start) or_return
		//
		// builder := strings.builder_make(int(sz.decompressed_size), allocator) or_return
		// defer { if err != nil { strings.builder_destroy(&builder) } }
		//
		// compressed_size := i64(base.hdr.size) - hdr_size
		// inflate(strings.to_stream(&builder), base.file.reader, int(compressed_size)) or_return
		//
		// data = builder.buf[:]
		// return

	case:
		err = .Unsupported_Compression_Type
		return
	}
}

Unimplemented_Section :: struct {
	using base: Section_Base,
}

String_Table :: struct {
	using base: Section_Base,
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
	using base: Section_Base,
	str_table:  String_Table,
}

Symbol :: struct {
	name:  u32,
	value: u64,
	size:  u64,
	info:  byte,    // TODO: bitfield, 4 bits `bind`, 4 bits `type`.
	other: byte,    // TODO: bitfield, 3 bits `local`, 2 bits padding, 3 bits `visibility`.
	shndx: u16,
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

		read_u16(file, &sym.shndx) or_return

	case .Bits_64:
		read_u32(file, &sym.name) or_return

		sym.info  = io.read_byte(file.reader) or_return
		sym.other = io.read_byte(file.reader) or_return

		read_u16(file, &sym.shndx) or_return

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
