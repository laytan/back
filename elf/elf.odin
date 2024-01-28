package elf

import "core:encoding/endian"
import "core:io"
import "core:mem"

import "../dwarf"

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
	Unsupported_Compression_Type,
	Decompress_Failure,
}

File :: struct {
	allocator:   mem.Allocator,

	reader:      io.Reader,
	reader_len:  i64,

	header:      Ehdr,
	hdr_str_tbl: String_Table,

	section_name_map: map[string]int,
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

file_init :: proc(file: ^File, reader: io.Reader, allocator := context.allocator) -> Error {
	file.allocator = allocator

	file.reader = reader
	file.reader_len = io.size(reader) or_return

	parse_header(file) or_return

	file.hdr_str_tbl = get_hdr_string_table(file) or_return

	return nil
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

iter_sections :: proc(file: ^File, idx: ^int, err: ^Error) -> (section: Section, ok: bool) {
	hdr := iter_section_headers(file, idx, err) or_return

	serr: Error
	section, serr = make_section(file, idx^-1, hdr)
	if serr != nil {
		err^ = serr
		ok   = false
		return
	}

	ok = true
	return
}

// Returns the section name, copied to the given allocator.
copy_section_name :: proc(file: ^File, hdr: Shdr, allocator := context.allocator) -> (string, Error) {
	return get_string(&file.hdr_str_tbl, int(hdr.name), allocator)
}

// Returns the interned section name of a section number, the string is destroyed with `file_destroy`.
section_name :: proc(file: ^File, n: int) -> (name: string, err: Error) {
	make_section_name_map(file) or_return

	for sname, sn in file.section_name_map {
		if sn == n {
			return sname, nil
		}
	}

	return
}

get_section_header_by_name :: proc(file: ^File, name: string) -> (hdr: Maybe(Shdr), err: Error) {
	make_section_name_map(file) or_return
	if name not_in file.section_name_map {
		return
	}

	return get_section_header(file, file.section_name_map[name])
}

get_section_by_name :: proc(file: ^File, name: string) -> (section: Section, err: Error) {
	make_section_name_map(file) or_return
	if name not_in file.section_name_map {
		return
	}

	n := file.section_name_map[name]
	hdr := get_section_header(file, n) or_return
	return make_section(file, n, hdr)
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


has_dwarf_info :: proc(file: ^File) -> (has: bool, err: Error) {
	make_section_name_map(file) or_return
	return (
		".debug_info"  in file.section_name_map ||
		".zdebug_info" in file.section_name_map ||
		".eh_frame"    in file.section_name_map \
	), nil
}

Debug_Sections :: enum {
	Debug_Info,
	Debug_Aranges,
	Debug_Abbrev,
	Debug_Str,
	Debug_Line,
	Debug_Frame,
	Debug_Loc,
	Debug_Ranges,
	Debug_Pubtypes,
	Debug_Pubnames,
	Debug_Addr,
	Debug_Str_Offsets,
	Debug_Line_Str,
	Debug_Loclists,
	Debug_Rnglists,
	Debug_Sup,
	Gnu_Debugaltlink,
	Eh_Frame,
}

DEBUG_SECTION_NAMES := [Debug_Sections]string{
	.Debug_Info        = ".debug_info",
	.Debug_Aranges     = ".debug_aranges",
	.Debug_Abbrev      = ".debug_abbrev",
	.Debug_Str         = ".debug_str",
	.Debug_Line        = ".debug_line",
	.Debug_Frame       = ".debug_frame",
	.Debug_Loc         = ".debug_loc",
	.Debug_Ranges      = ".debug_ranges",
	.Debug_Pubtypes    = ".debug_pubtypes",
	.Debug_Pubnames    = ".debug_pubnames",
	.Debug_Addr        = ".debug_addr",
	.Debug_Str_Offsets = ".debug_str_offsets",
	.Debug_Line_Str    = ".debug_line_str",
	.Debug_Loclists    = ".debug_loclists",
	.Debug_Rnglists    = ".debug_rnglists",
	.Debug_Sup         = ".debug_sup",
	.Gnu_Debugaltlink  = ".gnu_debugaltlink",
	.Eh_Frame          = ".eh_frame",
}

COMPRESSED_DEBUG_SECTION_NAMES := [Debug_Sections]string{
	.Debug_Info        = ".zdebug_info",
	.Debug_Aranges     = ".zdebug_aranges",
	.Debug_Abbrev      = ".zdebug_abbrev",
	.Debug_Str         = ".zdebug_str",
	.Debug_Line        = ".zdebug_line",
	.Debug_Frame       = ".zdebug_frame",
	.Debug_Loc         = ".zdebug_loc",
	.Debug_Ranges      = ".zdebug_ranges",
	.Debug_Pubtypes    = ".zdebug_pubtypes",
	.Debug_Pubnames    = ".zdebug_pubnames",
	.Debug_Addr        = ".zdebug_addr",
	.Debug_Str_Offsets = ".zdebug_str_offsets",
	.Debug_Line_Str    = ".zdebug_line_str",
	.Debug_Loclists    = ".zdebug_loclists",
	.Debug_Rnglists    = ".zdebug_rnglists",
	.Debug_Sup         = ".zdebug_sup",
	.Gnu_Debugaltlink  = ".zgnu_debugaltlink",
	.Eh_Frame          = ".eh_frame",
}

dwarf_info :: proc(file: ^File, relocate_dwarf_sections := true, follow_links := true) -> (info: dwarf.Info, err: Error) {
	_, compressed := (get_section_header_by_name(file, ".zdebug_info") or_return).?
	names := &COMPRESSED_DEBUG_SECTION_NAMES if compressed else &DEBUG_SECTION_NAMES

	dwarf_section :: proc(file: ^File, name: string, relocate_dwarf_sections: bool) -> (desc: Maybe(dwarf.Debug_Section_Descriptor), err: Error) {
		section := get_section_by_name(file, name) or_return
		if section == nil { return }

		ddesc := read_dwarf_section(file, section, relocate_dwarf_sections) or_return
		if name[1] == 'z' {
			decompress_dwarf_section(file, &ddesc)
		}
		return ddesc, nil
	}

	default_address_size := 8 if file.header.ident.class == .Bits_64 else 4

	rds := relocate_dwarf_sections

	info = dwarf.Info{
		reader = file.reader,
		config = dwarf.Config{
			little_endian        = file.header.ident.data == .Little,
			default_address_size = default_address_size,
			// machine_arch = self.get_machine_arch(),
		},
		debug_info        = dwarf_section(file, names[.Debug_Info],        rds) or_return,
		debug_aranges     = dwarf_section(file, names[.Debug_Aranges],     rds) or_return,
		debug_abbrev      = dwarf_section(file, names[.Debug_Abbrev],      rds) or_return,
		debug_str         = dwarf_section(file, names[.Debug_Str],         rds) or_return,
		debug_line        = dwarf_section(file, names[.Debug_Line],        rds) or_return,
		debug_frame       = dwarf_section(file, names[.Debug_Frame],       rds) or_return,
		debug_loc         = dwarf_section(file, names[.Debug_Loc],         rds) or_return,
		debug_ranges      = dwarf_section(file, names[.Debug_Ranges],      rds) or_return,
		debug_pubtypes    = dwarf_section(file, names[.Debug_Pubtypes],    rds) or_return,
		debug_pubnames    = dwarf_section(file, names[.Debug_Pubnames],    rds) or_return,
		debug_addr        = dwarf_section(file, names[.Debug_Addr],        rds) or_return,
		debug_str_offsets = dwarf_section(file, names[.Debug_Str_Offsets], rds) or_return,
		debug_line_str    = dwarf_section(file, names[.Debug_Line_Str],    rds) or_return,
		debug_loclists    = dwarf_section(file, names[.Debug_Loclists],    rds) or_return,
		debug_rnglists    = dwarf_section(file, names[.Debug_Rnglists],    rds) or_return,
		debug_sup         = dwarf_section(file, names[.Debug_Sup],         rds) or_return,
		gnu_debugaltlink  = dwarf_section(file, names[.Gnu_Debugaltlink],  rds) or_return,
		eh_frame          = dwarf_section(file, names[.Eh_Frame],          rds) or_return,
	}
	return
}

get_section :: proc(file: ^File, n: int) -> (section: Section, err: Error) {
	hdr := get_section_header(file, n) or_return
	return make_section(file, n, hdr)
}

@(private)
read_dwarf_section :: proc(file: ^File, section: Section, relocate_dwarf_sections: bool) -> (descriptor: dwarf.Debug_Section_Descriptor, err: Error) {
	// TODO: bunch of duplication here, mainly getting size 2/3 times.

	base := section_base(section)
	data := section_data(section) or_return

	if relocate_dwarf_sections {
		panic("todo: relocate_dwarf_sections")
	}

	descriptor = {
		data          = data,
		name          = base.name,
		global_offset = base.hdr.offset,
		size          = (section_size(section) or_return).decompressed_size,
		address       = base.hdr.addr,
	}
	return
}

@(private)
decompress_dwarf_section :: proc(file: ^File, desc: ^dwarf.Debug_Section_Descriptor) {
	panic("todo: decompress_dwarf_section")
}

@(private)
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

@(private)
get_hdr_string_table :: proc(file: ^File) -> (tbl: String_Table, err: Error) {
	tbl.file = file
	stringtable_num := get_shstrndx(file) or_return
	tbl.hdr = get_section_header(file, stringtable_num) or_return
	return
}

@(private)
make_section_name_map :: proc(file: ^File) -> Error {
	if file.section_name_map != nil {
		return nil
	}

	file.section_name_map = make(map[string]int, allocator=file.allocator)

	idx: int
	err: Error
	for hdr in iter_section_headers(file, &idx, &err) {
		name := copy_section_name(file, hdr, file.allocator) or_return
		file.section_name_map[name] = idx-1
	}

	return nil
}

@(private)
make_section :: proc(file: ^File, n: int, shdr: Shdr) -> (section: Section, err: Error) {
	make_section_name_map(file) or_return

	name := section_name(file, n) or_return

	base := Section_Base{
		name = name,
		file = file,
		hdr  = shdr,
	}

	#partial switch shdr.type {
	case .STRTAB:
		section = String_Table{ base = base }
		return
	case .SYMTAB, .DYNSYM, .SUNW_LDYNSYM:
		strtab := get_section(file, int(shdr.link)) or_return
		section = Symbol_Table{ base = base, str_table = strtab.(String_Table) }
		return
	case:
		section = base
		return
	}
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
