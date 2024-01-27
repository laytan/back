package elf

import "core:encoding/endian"
import "core:io"
import "core:mem"

Error :: union #shared_nil {
	File_Error,
	io.Error,
	mem.Allocator_Error,
}

File_Error :: enum {
	None,
	Magic_Mismatch,
	Invalid_EI_Class,
	Invalid_EI_Data,
}

File :: struct {
	reader:      io.Reader,
	reader_len:  i64,
	header:      Ehdr,
	hdr_str_tbl: String_Table,
}

Ehdr :: struct {
	ident: Ident,

	type:      Type,
	machine:   Machine,
	version:   u32,
	entry:     u64,
	phoff:     u64,
	shoff:     u64,
	flags:     u32,
	ehsize:    u16,
	phentsize: u16,
	phnum:     u16,
	shentsize: u16,
	shnum:     u16,
	shstrndx:  u16,
}

Ident :: struct {
	magic:       [4]byte,
	class:       EI_Class,
	data:        EI_Data,
	version:     Version,
	os_abi:      EI_OSABI,
	abi_version: byte,
	_:           [7]byte,
}

Shdr :: struct {
	name:      u32,
	type:      Section_Type,
	flags:     u64,
	addr:      u64,
	offset:    u64,
	size:      u64,
	link:      u32,
	info:      u32,
	addralign: u64,
	entsize:   u64,
}

file_init :: proc(file: ^File, reader: io.Reader) -> Error {
	file.reader = reader
	file.reader_len = io.size(reader) or_return

	parse_header(file) or_return

	file.hdr_str_tbl = get_hdr_string_table(file) or_return

	return nil
}

get_section_header :: proc(file: ^File, n: int) -> (hdr: Shdr, err: Error) {
	off := section_offset(file, n)
	io.seek(file.reader, off, .Start) or_return

	read_u32 (file, &hdr.name)         or_return
	read_u32 (file, (^u32)(&hdr.type)) or_return
	read_uint(file, &hdr.flags)        or_return
	read_uint(file, &hdr.addr)         or_return
	read_uint(file, &hdr.offset)       or_return
	read_uint(file, &hdr.size)         or_return
	read_u32 (file, &hdr.link)         or_return
	read_u32 (file, &hdr.info)         or_return
	read_uint(file, &hdr.addralign)    or_return
	read_uint(file, &hdr.entsize)      or_return

	return
}

get_shstrndx :: proc(file: ^File) -> (idx: int, err: Error) {
	// From https://refspecs.linuxfoundation.org/elf/gabi4+/ch4.eheader.html:
	// If the section name string table section index is greater than or
	// equal to SHN_LORESERVE (0xff00), this member has the value SHN_XINDEX
	// (0xffff) and the actual index of the section name string table section
	// is contained in the sh_link field of the section header at index 0.
	SHN_XINDEX :: 0xffff

	if file.header.shstrndx != SHN_XINDEX {
		return int(file.header.shstrndx), nil
	}

	first_hdr := get_section_header(file, 0) or_return
	return int(first_hdr.link), nil
}

num_sections :: proc(file: ^File) -> (num: int, err: Error) {
	if file.header.shoff == 0 {
		return 0, nil
	}

	if file.header.shnum == 0 {
		// TODO: this can be called a bunch, should cache this first section probably.
		first_hdr := get_section_header(file, 0) or_return
		return int(first_hdr.size), nil
	}

	return int(file.header.shnum), nil
}

iter_section_headers :: proc(file: ^File, idx: ^int, err: ^Error) -> (hdr: Shdr, ok: bool) {
	defer idx^ = idx^ + 1

	sections, serr := num_sections(file)
	if serr != nil {
		err^ = serr
		return
	}

	if idx^ >= sections {
		return
	}

	hdr, serr = get_section_header(file, idx^)
	if serr != nil {
		err^ = serr
		return
	}

	ok = true
	return
}

section_name :: proc(file: ^File, hdr: Shdr, allocator := context.allocator) -> (string, Error) {
	return get_string(&file.hdr_str_tbl, int(hdr.name), allocator)
}

@(private)
get_hdr_string_table :: proc(file: ^File) -> (tbl: String_Table, err: Error) {
	tbl.file = file
	stringtable_num := get_shstrndx(file) or_return
	tbl.hdr = get_section_header(file, stringtable_num) or_return
	return
}

@(private)
parse_header :: proc(file: ^File) -> Error {
	ELF_MAGIC :: [4]byte{ 0x7f, 'E', 'L', 'F' }

	io.seek(file.reader, 0, .Start) or_return

	ident := &file.header.ident

	ident_bytes := ([^]byte)(ident)[:size_of(Ident)]
	io.read_full(file.reader, ident_bytes[:]) or_return

	if ident.magic != ELF_MAGIC {
		return .Magic_Mismatch
	}

	if !is_enum_known_value(ident.class) {
		return .Invalid_EI_Class
	}

	if !is_enum_known_value(ident.data) {
		return .Invalid_EI_Data
	}

	read_u16 (file, (^u16)(&file.header.type))    or_return
	read_u16 (file, (^u16)(&file.header.machine)) or_return
	read_u32 (file, &file.header.version)         or_return
	read_uint(file, &file.header.entry)           or_return
	read_uint(file, &file.header.phoff)           or_return
	read_uint(file, &file.header.shoff)           or_return
	read_u32 (file, &file.header.flags)           or_return
	read_u16 (file, &file.header.ehsize)          or_return
	read_u16 (file, &file.header.phentsize)       or_return
	read_u16 (file, &file.header.phnum)           or_return
	read_u16 (file, &file.header.shentsize)       or_return
	read_u16 (file, &file.header.shnum)           or_return
	read_u16 (file, &file.header.shstrndx)        or_return

	return nil
}

@(private)
section_offset :: proc(file: ^File, n: int) -> i64 {
	return i64(file.header.shoff) + i64(n) * i64(file.header.shentsize)
}

@(private)
read_u16 :: proc(file: ^File, target: ^u16) -> Error {
	buf: [size_of(u16)]byte = ---
	io.read_full(file.reader, buf[:]) or_return

	switch file.header.ident.data {
	case .Big:    target^ = endian.unchecked_get_u16be(buf[:])
	case .Little: target^ = endian.unchecked_get_u16le(buf[:])
	case:         unreachable()
	}
	return nil
}

@(private)
read_u32 :: proc(file: ^File, target: ^u32) -> Error {
	buf: [size_of(u32)]byte = ---
	io.read_full(file.reader, buf[:]) or_return

	switch file.header.ident.data {
	case .Big:    target^ = endian.unchecked_get_u32be(buf[:])
	case .Little: target^ = endian.unchecked_get_u32le(buf[:])
	case:         unreachable()
	}
	return nil
}

@(private)
read_u64 :: proc(file: ^File, target: ^u64) -> Error {
	buf: [size_of(u64)]byte = ---
	io.read_full(file.reader, buf[:]) or_return

	switch file.header.ident.data {
	case .Big:    target^ = endian.unchecked_get_u64be(buf[:])
	case .Little: target^ = endian.unchecked_get_u64le(buf[:])
	case:         unreachable()
	}
	return nil
}

@(private)
read_uint :: proc(file: ^File, target: ^u64) -> Error {
	switch file.header.ident.class {
	case .Bits_64:
		return read_u64(file, target)
	case .Bits_32:
		inter: u32
		read_u32(file, &inter) or_return
		target^ = u64(inter)
	case:
		unreachable()
	}
	return nil
}
