package dwarf

import "core:encoding/endian"
import "core:io"
import "core:mem"
import "core:strings"

Info :: struct {
	reader:            io.Reader,
	config:            Config,
	debug_info:        Maybe(Debug_Section_Descriptor),
	debug_aranges:     Maybe(Debug_Section_Descriptor),
	debug_abbrev:      Maybe(Debug_Section_Descriptor),
	debug_line:        Maybe(Debug_Section_Descriptor),
	debug_str:         Maybe(Debug_Section_Descriptor),
	debug_frame:       Maybe(Debug_Section_Descriptor),
	debug_loc:         Maybe(Debug_Section_Descriptor),
	debug_ranges:      Maybe(Debug_Section_Descriptor),
	debug_pubtypes:    Maybe(Debug_Section_Descriptor),
	debug_pubnames:    Maybe(Debug_Section_Descriptor),
	debug_addr:        Maybe(Debug_Section_Descriptor),
	debug_str_offsets: Maybe(Debug_Section_Descriptor),
	debug_line_str:    Maybe(Debug_Section_Descriptor),
	debug_loclists:    Maybe(Debug_Section_Descriptor),
	debug_rnglists:    Maybe(Debug_Section_Descriptor),
	debug_sup:         Maybe(Debug_Section_Descriptor),
	gnu_debugaltlink:  Maybe(Debug_Section_Descriptor),
	eh_frame:          Maybe(Debug_Section_Descriptor),
}

Config :: struct {
	little_endian:        bool,
	default_address_size: int,
}

Debug_Section_Descriptor :: struct {
	data:          []byte `fmt:"-"`,
	name:          string,
	global_offset: u64,
	size:          u64,
	address:       u64,
}

Error :: union #shared_nil {
	io.Error,
	mem.Allocator_Error,
}

iter_CUs :: proc(info: Info, off: ^u64, err: ^Error) -> (cu: CU, ok: bool) {
	debug_info := info.debug_info.? or_return

	if off^ >= debug_info.size { return }

	cu_err: Error
	cu, cu_err = parse_CU_at_offset(info, debug_info, off^)
	if cu_err != nil {
		err^ = cu_err
		return
	}

	ok = true

	initial_length_size := 12 if cu.hdr.format == .Bits_64 else 4
	off^ = off^ + cu.hdr.unit_length + u64(initial_length_size)

	return
}

CU :: struct {
	hdr:        CU_Header,
	offset:     u64,
	die_offset: u64,
}

CU_Header :: struct {
	format:              Bits,
	unit_length:         u64,
	version:             u16,
	debug_abbrev_offset: u64,
	address_size:        u8,
}

Bits :: enum {
	Bits_32,
	Bits_64,
}

parse_CU_at_offset :: proc(info: Info, debug_info: Debug_Section_Descriptor, off: u64) -> (cu: CU, err: Error) {
	cu.offset = off

	global_off := debug_info.global_offset + off
	io.seek(info.reader, i64(global_off), .Start) or_return

	first_word: u32
	read_u32(info, &first_word) or_return
	cu.hdr.format = .Bits_64 if first_word == 0xFFFFFFFF else .Bits_32

	switch cu.hdr.format {
	case .Bits_64:
		read_u64(info, &cu.hdr.unit_length) or_return
	case .Bits_32: cu.hdr.unit_length = 4
		cu.hdr.unit_length = u64(first_word)
	}

	read_u16(info, &cu.hdr.version) or_return

	if cu.hdr.version != 4 {
		panic("todo: DWARF version != 4")
	}

	read_uint(info, cu.hdr.format, &cu.hdr.debug_abbrev_offset) or_return
	cu.hdr.address_size = io.read_byte(info.reader) or_return

	curr := u64(io.seek(info.reader, 0, .Current) or_return)
	cu.die_offset = curr - debug_info.global_offset

	// TODO: rest of the CU.
	return
}

DIE :: struct {
	offset:      u64,
	abbrev_code: u64,
	attributes:  map[At]Attr_Value,
}

Attr_Value :: union {
	u64,
	u128,
	i64,
}

top_DIE :: proc(info: Info, cu: CU, allocator := context.allocator) -> (die: DIE, err: Error) {
	die.attributes.allocator = allocator
	die.offset = cu.die_offset
	parse_die(info, cu, &die) or_return
	return
}

parse_die :: proc(info: Info, cu: CU, die: ^DIE) -> (err: Error) {
	debug_info := info.debug_info.?
	off := debug_info.global_offset + die.offset
	io.seek(info.reader, i64(off), .Start) or_return

	read := read_uleb128(info, &die.abbrev_code) or_return

	if die.abbrev_code == 0 {
		return nil
	}

	abbrev      := abbrev_table(info, cu.hdr.debug_abbrev_offset)
	abbrev_decl := get_abbrev(info, abbrev, die.abbrev_code) or_return

	die_off := off + read

	iter_state := iter_abbr_attrs_init(info, abbrev_decl)
	for spec in iter_abbr_attrs(info, &iter_state, &err) {
		io.seek(info.reader, i64(die_off), .Start) or_return

		form := spec.form
		name := spec.name
		value: Attr_Value

		switch form {
		case .null: unreachable()

		case .implicit_const:
			value = spec.value

		case .indirect:
			panic("todo: indirect attributes")

		// uleb128.
		case .addrx, .udata, .ref_udata, .loclistx, .rnglistx:
			raw_value: u64
			die_off += read_uleb128(info, &raw_value) or_return
			value = raw_value

		// sleb128.
		case .sdata:
			raw_value: i64
			die_off += read_sleb128(info, &raw_value) or_return
			value = raw_value

		// u8.
		case .addrx1, .data1, .strx1, .flag, .ref1:
			value = u64(io.read_byte(info.reader) or_return)
			die_off += 1

		// u16.
		case .addrx2, .data2, .strx2, .ref2:
			raw_value: u16
			read_u16(info, &raw_value) or_return
			value = u64(raw_value)
			die_off += size_of(u16)

		// u24.
		case .addrx3, .strx3:
			panic("unimplemented: u24")

		// u32.
		case .addrx4, .data4, .strx4, .ref, .ref4, .ref_sup4:
			raw_value: u32
			read_u32(info, &raw_value) or_return
			value = u64(raw_value)
			die_off += size_of(u32)

		// u64.
		case .data8, .ref8, .ref_sup8, .ref_sig8:
			raw_value: u64
			read_u64(info, &raw_value) or_return
			value = u64(raw_value)
			die_off += size_of(u64)

		// u128.
		case .data16:
			panic("unimplemented: u128")

		// cstring.
		case .string:
			panic("unimplemented: cstring")

		// (u32 if address size 4 else u64) if dwarf version 2 else (u32 if dwarf format 32 else u64).
		case .addr, .ref_addr:
			// NOTE: not checking for dwarf version 2 here.
			fallthrough

		// offset: u32 if dwarf format 32 else u64.
		case .strp, .strp_sup, .line_strp, .sec_offset, .GNU_strp_alt, .GNU_ref_alt:
			raw_value: u64
			read_uint(info, cu.hdr.format, &raw_value)
			value = raw_value
			die_off += size_of(u64)

		// I think this is an empty value, just signaling presence.
		case .flag_present:
			value = nil

		case .exprloc, .block1, .block2, .block4, .block, .strx, .GNU_addr_index, .GNU_str_index:
			fallthrough

		case:
			panic("unimplemented attr form")
		}

		die.attributes[name] = value
	}
	if err != nil { return }

	return nil
}

Abbrev_Table :: struct {
	offset: u64,
}

abbrev_table :: proc(info: Info, offset: u64) -> (abbrev_table: Abbrev_Table) {
	abbrev_table.offset = offset
	return
}

Abbrev_Decl :: struct {
	tag:          Abbrev_Decl_Tag,
	children:     b8,
	attrs_offset: u64,
}

Attr_Spec :: struct {
	name:  At,
	form:  Form,
	value: u64,
}

get_abbrev :: proc(info: Info, tbl: Abbrev_Table, code: u64) -> (decl: Abbrev_Decl, err: Error) {
	debug_abbrev := info.debug_abbrev.?
	off := debug_abbrev.global_offset + tbl.offset
	io.seek(info.reader, i64(off), .Start) or_return

	for {
		decl_code: u64
		read_uleb128(info, &decl_code) or_return
		if decl_code == 0 { break }

		read_uleb128(info, (^u64)(&decl.tag)) or_return

		decl.children = b8(io.read_byte(info.reader) or_return)

		if decl_code == code {
			curr := io.seek(info.reader, 0, .Current) or_return
			decl.attrs_offset = u64(curr) - debug_abbrev.global_offset
			return
		}

		attr: Attr_Spec
		for {
			read_uleb128(info, (^u64)(&attr.name)) or_return
			read_uleb128(info, (^u64)(&attr.form)) or_return
			if attr.form == .implicit_const {
				read_uleb128(info, &attr.value) or_return
			}

			if attr.name == .null && attr.form == .null {
				break
			}
		}
	}

	err = .Unexpected_EOF
	return
}

iter_abbr_attrs_init :: proc(info: Info, decl: Abbrev_Decl) -> i64 {
	debug_abbrev := info.debug_abbrev.?
	return i64(debug_abbrev.global_offset + decl.attrs_offset)
}

iter_abbr_attrs :: proc(info: Info, off: ^i64, err: ^Error) -> (attr: Attr_Spec, ok: bool) {
	_, err^ = io.seek(info.reader, off^, .Start)
	if err^ != nil { return }

	n_len, f_len, v_len: u64

	n_len, err^ = read_uleb128(info, (^u64)(&attr.name))
	if err^ != nil { return }

	f_len, err^ = read_uleb128(info, (^u64)(&attr.form))
	if err^ != nil { return }

	if attr.form == .implicit_const {
		v_len, err^ = read_uleb128(info, &attr.value)
		if err^ != nil { return }
	}

	if attr.name == .null && attr.form == .null {
		return
	}

	ok = true
	off^ = off^ + i64(n_len + f_len + v_len)
	return
}

Line_Program :: struct {
	hdr:       Line_Program_Header,
	start_off: u64,
	end_off:   u64,
}

Line_Program_Header :: struct {
	format:                             Bits,
	unit_length:                        u64,
	version:                            u16,
	header_length:                      u64,
	minimum_instruction_length:         u8,
	maximum_operations_per_instruction: u8,
	default_is_stmt:                    b8,
	line_base:                          i8,
	line_range:                         u8,
	opcode_base:                        u8,
	// TODO: don't allocate.
	standard_opcode_lengths:            []u8,
	include_directories:                []string,
	file_entries:                       [dynamic]File_Entry,
}

File_Entry :: struct {
	name: string,
	dir_index: u64,
	mtime: u64,
	length: u64,
}

line_program_for_CU :: proc(info: Info, cu: CU, allocator := context.allocator) -> (lp: Maybe(Line_Program), err: Error) {
	if _, has_debug_line_sect := info.debug_line.?; !has_debug_line_sect {
		return
	}

	top_die := top_DIE(info, cu, allocator) or_return

	if off, has_list := top_die.attributes[.stmt_list]; has_list {
		return parse_line_program_at_offset(info, off.(u64), allocator)
	}

	return
}

Line_Program_Entry :: struct {
	command: Line_Program_Opcode,
	is_extended: bool,
	state: Maybe(Line_State),
}

Line_State :: struct {
	address:        int,
	file:           int,
	line:           int,
	column:         int,
	op_index:       int,
	is_stmt:        bool,
	basic_block:    bool,
	end_sequence:   bool,
	prologue_end:   bool,
	epilogue_begin: bool,
	isa:            int,
	discriminator:  int,
}

make_line_state :: proc(is_stmt: bool) -> (s: Line_State) {
	s.is_stmt = is_stmt
	s.file    = 1
	s.line    = 1
	return
}

Line_Program_Opcode :: enum u8 {
	LNS_copy               = 0x01,
	LNS_advance_pc         = 0x02,
	LNS_advance_line       = 0x03,
	LNS_set_file           = 0x04,
	LNS_set_column         = 0x05,
	LNS_negate_stmt        = 0x06,
	LNS_set_basic_block    = 0x07,
	LNS_const_add_pc       = 0x08,
	LNS_fixed_advance_pc   = 0x09,
	LNS_set_prologue_end   = 0x0a,
	LNS_set_epilogue_begin = 0x0b,
	LNS_set_isa            = 0x0c,
	LNE_end_sequence       = 0x01,
	LNE_set_address        = 0x02,
	LNE_define_file        = 0x03,
	LNE_set_discriminator  = 0x04,
	LNE_lo_user            = 0x80,
	LNE_hi_user            = 0xff,
}

decode_line_program :: proc(info: Info, cu: CU, lp: ^Line_Program, allocator := context.allocator) -> (result: []Line_Program_Entry, err: Error) {
	entries := make([dynamic]Line_Program_Entry, allocator)
	defer { if err != nil { delete(entries) } }

	add_entry_new_state :: proc(entries: ^[dynamic]Line_Program_Entry, state: ^Line_State, cmd: Line_Program_Opcode, is_extended := false) -> Error {
		append(entries, Line_Program_Entry{
			command     = cmd,
			is_extended = is_extended,
			state       = state^,
		}) or_return
		state.discriminator  = 0
		state.basic_block    = false
		state.prologue_end   = false
		state.epilogue_begin = false
		return nil
	}

	add_entry_old_state :: proc(entries: ^[dynamic]Line_Program_Entry, cmd: Line_Program_Opcode, is_extended := false) -> Error {
		append(entries, Line_Program_Entry{
			command     = cmd,
			is_extended = is_extended,
		}) or_return
		return nil
	}

	state := make_line_state(bool(lp.hdr.default_is_stmt))

	global_off := (info.debug_line.?).global_offset
	offset     := global_off + lp.start_off
	end_offset := global_off + lp.end_off
	io.seek(info.reader, i64(offset), .Start) or_return

	for offset < end_offset {
		opcode := io.read_byte(info.reader) or_return

		switch {
		case opcode >= lp.hdr.opcode_base:
			adjusted_opcode   := int(opcode - lp.hdr.opcode_base)
			operation_advance := adjusted_opcode / int(lp.hdr.line_range)
			address_addend := (
				int(lp.hdr.minimum_instruction_length) *
				((state.op_index + operation_advance) / int(lp.hdr.maximum_operations_per_instruction)) \
			)
			state.address += address_addend
			state.op_index = (state.op_index + operation_advance) % int(lp.hdr.maximum_operations_per_instruction)
			line_addend := int(lp.hdr.line_base) + (adjusted_opcode % int(lp.hdr.line_range))
			state.line += line_addend

			add_entry_new_state(&entries, &state, Line_Program_Opcode(opcode)) or_return

		case opcode == 0:
			inst_len: u64
			read_uleb128(info, &inst_len) or_return

			ex_opcode := Line_Program_Opcode(io.read_byte(info.reader) or_return)

			#partial switch ex_opcode {
			case .LNE_end_sequence:
				state.end_sequence = true
				state.is_stmt = false
				add_entry_new_state(&entries, &state, ex_opcode, true) or_return

				// Reset state.
				state = make_line_state(bool(lp.hdr.default_is_stmt))

			case .LNE_set_address:
				operand: u64
				read_target_address(info, cu.hdr.address_size, &operand) or_return
				state.address = int(operand)
				add_entry_old_state(&entries, ex_opcode, true) or_return

			case .LNE_define_file:
				entry: File_Entry

				builder := strings.builder_make(allocator) or_return
				defer { if err != nil { strings.builder_destroy(&builder) } }

				read_cstring(info, strings.to_stream(&builder)) or_return
				entry.name = strings.to_string(builder)

				read_uleb128(info, &entry.dir_index) or_return
				read_uleb128(info, &entry.mtime)     or_return
				read_uleb128(info, &entry.length)    or_return

				append(&lp.hdr.file_entries, entry) or_return

				add_entry_old_state(&entries, ex_opcode, true) or_return

			case .LNE_set_discriminator:
				operand: u64
				read_uleb128(info, &operand) or_return
				state.discriminator = int(operand)

			case:
				// TODO: kinda dangerous to just skip, might need a log or something.

				// Unknown, but need to roll forward the stream because the
				// length is specified. Seek forward inst_len - 1 because
				// we've already read the extended opcode, which takes part
				// in the length.
				io.seek(info.reader, i64(inst_len)-1, .Current) or_return
			}
		case:
			std_opcode := Line_Program_Opcode(opcode)
			#partial switch std_opcode {
			case .LNS_copy:
				add_entry_new_state(&entries, &state, std_opcode) or_return

			case .LNS_advance_pc:
				operand: u64
				read_uleb128(info, &operand) or_return
				address_addend := operand * u64(lp.hdr.minimum_instruction_length)
				state.address += int(address_addend)
				add_entry_old_state(&entries, std_opcode) or_return

			case .LNS_advance_line:
				operand: i64
				read_sleb128(info, &operand) or_return
				state.line += int(operand)

			case .LNS_set_file:
				operand: u64
				read_uleb128(info, &operand) or_return
				state.file = int(operand)
				add_entry_old_state(&entries, std_opcode) or_return

			case .LNS_set_column:
				operand: u64
				read_uleb128(info, &operand) or_return
				state.column = int(operand)
				add_entry_old_state(&entries, std_opcode) or_return

			case .LNS_negate_stmt:
				state.is_stmt = !state.is_stmt
				add_entry_old_state(&entries, std_opcode) or_return

			case .LNS_set_basic_block:
				state.basic_block = true
				add_entry_old_state(&entries, std_opcode) or_return

			case .LNS_const_add_pc:
				adjusted_opcode := int(255 - lp.hdr.opcode_base)
				address_addend := ((adjusted_opcode / int(lp.hdr.line_range)) * int(lp.hdr.minimum_instruction_length))
				state.address += address_addend
				add_entry_old_state(&entries, std_opcode) or_return

			case .LNS_fixed_advance_pc:
				operand: u16
				read_u16(info, &operand) or_return
				state.address += int(operand)
				add_entry_old_state(&entries, std_opcode) or_return

			case .LNS_set_prologue_end:
				state.prologue_end = true
				add_entry_old_state(&entries, std_opcode) or_return

			case .LNS_set_epilogue_begin:
				state.epilogue_begin = true
				add_entry_old_state(&entries, std_opcode) or_return

			case .LNS_set_isa:
				operand: u64
				read_uleb128(info, &operand) or_return
				state.isa = int(operand)
				add_entry_old_state(&entries, std_opcode) or_return

			case:
				panic("invalid standard line program opcode")
			}
		}

		offset = u64(io.seek(info.reader, 0, .Current) or_return)
	}

	result = entries[:]
	return
}

@(private)
parse_line_program_at_offset :: proc(info: Info, off: u64, allocator := context.allocator) -> (lp: Line_Program, err: Error) {
	debug_line := info.debug_line.?

	global_off := debug_line.global_offset + off
	io.seek(info.reader, i64(global_off), .Start) or_return

	first_word: u32
	read_u32(info, &first_word) or_return
	lp.hdr.format = .Bits_64 if first_word == 0xFFFFFFFF else .Bits_32

	switch lp.hdr.format {
	case .Bits_64:
		read_u64(info, &lp.hdr.unit_length) or_return
	case .Bits_32: lp.hdr.unit_length = 4
		lp.hdr.unit_length = u64(first_word)
	}

	read_u16(info, &lp.hdr.version) or_return

	if lp.hdr.version != 4 {
		panic("todo: DWARF version != 4")
	}

	// PERF: might be able to read the entire header at once at this point.
	read_uint(info, lp.hdr.format, &lp.hdr.header_length) or_return

	lp.hdr.minimum_instruction_length         = io.read_byte(info.reader) or_return
	lp.hdr.maximum_operations_per_instruction = io.read_byte(info.reader) or_return
	lp.hdr.default_is_stmt                    = b8(io.read_byte(info.reader) or_return)
	lp.hdr.line_base                          = transmute(i8)(io.read_byte(info.reader) or_return)
	lp.hdr.line_range                         = io.read_byte(info.reader) or_return
	lp.hdr.opcode_base                        = io.read_byte(info.reader) or_return

	lp.hdr.standard_opcode_lengths = make([]u8, lp.hdr.opcode_base-1, allocator) or_return
	defer { if err != nil { delete(lp.hdr.standard_opcode_lengths, allocator) } }
	for &standard_opcode_length in lp.hdr.standard_opcode_lengths {
		standard_opcode_length = io.read_byte(info.reader) or_return
	}

	// TODO/PERF: first scan the size, and allocate once.
	include_directory := make([dynamic]string, allocator) or_return
	defer { if err != nil { delete(include_directory) } }
	for {
		builder := strings.builder_make(allocator) or_return
		read_cstring(info, strings.to_stream(&builder)) or_return
		if strings.builder_len(builder) == 0 {
			strings.builder_destroy(&builder)
			break
		}
		append(&include_directory, strings.to_string(builder)) or_return
	}
	lp.hdr.include_directories = include_directory[:]

	// TODO/PERF: calculate size up front.
	file_entry := make([dynamic]File_Entry, allocator) or_return
	defer { if err != nil { delete(file_entry) } }
	for {
		entry: File_Entry

		builder := strings.builder_make(allocator) or_return
		read_cstring(info, strings.to_stream(&builder)) or_return
		entry.name = strings.to_string(builder)

		if len(entry.name) == 0 {
			strings.builder_destroy(&builder)
			break
		}

		read_uleb128(info, &entry.dir_index) or_return
		read_uleb128(info, &entry.mtime)     or_return
		read_uleb128(info, &entry.length)    or_return

		append(&file_entry, entry)
	}
	lp.hdr.file_entries = file_entry

	curr := io.seek(info.reader, 0, .Current) or_return
	lp.start_off = u64(curr) - debug_line.global_offset

	initial_length_size := 12 if lp.hdr.format == .Bits_64 else 4
	lp.end_off = off + lp.hdr.unit_length + u64(initial_length_size)

	return
}

@(private)
read_u16 :: proc(info: Info, target: ^u16) -> Error {
	buf: [size_of(u16)]byte = ---
	io.read_full(info.reader, buf[:]) or_return

	switch info.config.little_endian {
	case false: target^ = endian.unchecked_get_u16be(buf[:])
	case true:  target^ = endian.unchecked_get_u16le(buf[:])
	}
	return nil
}

@(private)
read_u32 :: proc(info: Info, target: ^u32) -> Error {
	buf: [size_of(u32)]byte = ---
	io.read_full(info.reader, buf[:]) or_return

	switch info.config.little_endian {
	case false: target^ = endian.unchecked_get_u32be(buf[:])
	case true:  target^ = endian.unchecked_get_u32le(buf[:])
	}
	return nil
}

@(private)
read_u64 :: proc(info: Info, target: ^u64) -> Error {
	buf: [size_of(u64)]byte = ---
	io.read_full(info.reader, buf[:]) or_return

	switch info.config.little_endian {
	case false: target^ = endian.unchecked_get_u64be(buf[:])
	case true:  target^ = endian.unchecked_get_u64le(buf[:])
	}
	return nil
}

@(private)
read_i16 :: proc(info: Info, target: ^i16) -> Error {
	buf: [size_of(i16)]byte = ---
	io.read_full(info.reader, buf[:]) or_return

	switch info.config.little_endian {
	case false: target^ = transmute(i16)endian.unchecked_get_u16be(buf[:])
	case true:  target^ = transmute(i16)endian.unchecked_get_u16le(buf[:])
	}
	return nil
}

@(private)
read_i32 :: proc(info: Info, target: ^i32) -> Error {
	buf: [size_of(i32)]byte = ---
	io.read_full(info.reader, buf[:]) or_return

	switch info.config.little_endian {
	case false: target^ = transmute(i32)endian.unchecked_get_u32be(buf[:])
	case true:  target^ = transmute(i32)endian.unchecked_get_u32le(buf[:])
	}
	return nil
}

@(private)
read_i64 :: proc(info: Info, target: ^i64) -> Error {
	buf: [size_of(i64)]byte = ---
	io.read_full(info.reader, buf[:]) or_return

	switch info.config.little_endian {
	case false: target^ = transmute(i64)endian.unchecked_get_u64be(buf[:])
	case true:  target^ = transmute(i64)endian.unchecked_get_u64le(buf[:])
	}
	return nil
}

@(private)
read_uint :: proc(info: Info, bits: Bits, target: ^u64) -> Error {
	switch bits {
	case .Bits_64:
		return read_u64(info, target)
	case .Bits_32:
		inter: u32
		read_u32(info, &inter) or_return
		target^ = u64(inter)
	case:
		unreachable()
	}
	return nil
}

@(private)
read_target_address :: proc(info: Info, address_size: u8, target: ^u64) -> Error {
	switch address_size {
	case 8:
		return read_u64(info, target)
	case 4:
		inter: u32
		read_u32(info, &inter) or_return
		target^ = u64(inter)
	case:
		unreachable()
	}
	return nil
}

@(private)
read_uleb128 :: proc(info: Info, target: ^u64) -> (bytes_read: u64, err: Error) {
	result, shift: u64
	for {
		byte := io.read_byte(info.reader) or_return
		bytes_read += 1
		result |= u64(byte & 0x7F) << shift
		if (byte & 0x80) == 0 {
			break
		}
		shift += 7
	}

	target^ = result
	return
}

@(private)
read_sleb128 :: proc(info: Info, target: ^i64) -> (bytes_read: u64, err: Error) {
	result: i64
	shift: u64
	for {
		byte := io.read_byte(info.reader) or_return
		bytes_read += 1
		result |= i64(byte & 0x7F) << shift
		shift += 7
		if (byte & 0x80) == 0 {
			if shift < 64 && (byte & 0x40) != 0 {
				result |= (~i64(0) << shift)
			}
			break
		}
	}

	target^ = result
	return
}

@(private)
read_cstring :: proc(info: Info, dest: io.Stream) -> Error {
	for {
		byte := io.read_byte(info.reader) or_return
		if byte == 0 { break }
		io.write_byte(dest, byte) or_return
	}
	return nil
}
