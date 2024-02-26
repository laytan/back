package dwarf

import "core:io"
import "core:strings"

// TODO: don't import fmt.
import "core:fmt"

call_frame_info :: proc(info: Info, allocator := context.allocator) -> (result: []Entry, err: Error) {
	eh_frame, has_eh_frame := info.eh_frame.?
	if !has_eh_frame { return }

	global_offset := eh_frame.global_offset + 0

	entries := make([dynamic]Entry, allocator) or_return

	for global_offset < eh_frame.global_offset + eh_frame.size {
		append(&entries, parse_cfi_entry_at(info, global_offset) or_return)
		global_offset = u64(io.seek(info.reader, 0, .Current) or_return)
	}

	result = entries[:]
	return
}

parse_cfi_entry_at :: proc(info: Info, off: u64, allocator := context.allocator) -> (entry: Entry, err: Error) {
	io.seek(info.reader, i64(off), .Start) or_return

	hdr: CFI_Header

	first_word: u32
	read_u32(info, &first_word) or_return
	hdr.format = .Bits_64 if first_word == 0xFFFFFFFF else .Bits_32

	switch hdr.format {
	case .Bits_64:
		read_u64(info, &hdr.length) or_return
	case .Bits_32:
		hdr.length = u64(first_word)
	}

	if hdr.length == 0 {
		entry = Zero{off}
		return
	}

	read_uint(info, hdr.format, &hdr.cie_ptr) or_return

	if hdr.cie_ptr == 0 {
		return parse_cie(info, hdr, off, allocator)
	} else {
		return parse_fde(info, hdr, off, allocator)
	}
}

parse_cie :: proc(info: Info, hdr: CFI_Header, off: u64, allocator := context.allocator) -> (cie: CIE, err: Error) {
	cie.header = hdr

	cie.version = io.read_byte(info.reader) or_return

	// NOTE: I think this version is not the dwarf version.
	// if cie.version != 4 {
	// 	panic("unimplemented: dwarf version != 4")
	// }

	// TODO: just store like 8 bytes, or even just iterate over it directly below, don't need
	// to store when we have already parsed it.
	augmentation_builder := strings.builder_make(allocator)
	defer { if err != nil { strings.builder_destroy(&augmentation_builder) } }
	read_cstring(info, strings.to_stream(&augmentation_builder)) or_return
	cie.augmentation = strings.to_string(augmentation_builder)

	read_uleb128(info, &cie.code_alignment_factor)   or_return
	read_sleb128(info, &cie.data_alignment_factor)   or_return
	read_uleb128(info, &cie.return_address_register) or_return

	for b in transmute([]byte)cie.augmentation {
		switch b {
		case 'z':
			length: u64
			read_uleb128(info, &length) or_return
			cie.augmentations[.Length] = length

		case 'L':
			cie.augmentations[.LSDA_Encoding] = io.read_byte(info.reader) or_return

		case 'R':
			cie.augmentations[.FDE_Encoding] = io.read_byte(info.reader) or_return

		case 'S':
			cie.augmentations[.S] = true

		case 'P':
			encoding := io.read_byte(info.reader) or_return
			switch Eh_Encoding_Flags(encoding & 0x0f) {
			case .absptr:
				// NOTE: is this the correct address size?
				val: u64
				read_target_address(info, u8(info.config.default_address_size), &val) or_return
				cie.augmentations[.Personality] = val

			case .uleb128:
				val: u64
				read_uleb128(info, &val) or_return
				cie.augmentations[.Personality] = val

			case .udata2:
				val: u16
				read_u16(info, &val) or_return
				cie.augmentations[.Personality] = u64(val)

			case .udata4:
				val: u32
				read_u32(info, &val) or_return
				cie.augmentations[.Personality] = u64(val)

			case .udata8:
				val: u64
				read_u64(info, &val) or_return
				cie.augmentations[.Personality] = u64(val)

			case .sleb128:
				val: i64
				read_sleb128(info, &val) or_return
				cie.augmentations[.Personality] = i64(val)

			case .sdata2:
				val: i16
				read_i16(info, &val) or_return
				cie.augmentations[.Personality] = i64(val)

			case .sdata4:
				val: i32
				read_i32(info, &val) or_return
				cie.augmentations[.Personality] = i64(val)

			case .sdata8:
				val: i64
				read_i64(info, &val) or_return
				cie.augmentations[.Personality] = val

			case .omit:
			case .signed, .pcrel, .textrel, .datarel, .funcrel, .aligned, .indirect:
				fallthrough
			case:
				panic("unimplemented eh personality encoding")
			}
		case:
			panic("unknown augmentation")
		}
	}

	initial_length_size := u64(12 if hdr.format == .Bits_64 else 4)
	end_offset := off + hdr.length + initial_length_size
	cie.instructions = parse_instructions(info, end_offset, allocator) or_return
	return
}

parse_fde :: proc(info: Info, hdr: CFI_Header, off: u64, allocator := context.allocator) -> (fde: FDE, err: Error) {
	eh_frame := info.eh_frame.?
	fde.header = hdr

	fde_off := io.seek(info.reader, 0, .Current) or_return

	// Parse the CIE.
	uint_size  := u64(4 if hdr.format == .Bits_32 else 8)
	cie_offset := off + uint_size - hdr.cie_ptr
	cie_entry  := parse_cfi_entry_at(info, cie_offset, allocator) or_return
	cie        := cie_entry.(CIE)

	// Seek back to the FDE.
	io.seek(info.reader, fde_off, .Start) or_return

	_encoding := cie.augmentations[.FDE_Encoding]
	encoding, has_encoding := _encoding.(u8)
	if !has_encoding {
		panic("cie of fde has no encoding set, we need it to parse a meaningfull fde")
	}

	basic_encoding    := encoding & 0x0f
	encoding_modifier := encoding & 0xf0

	// TODO: based on encoding, parse initial_location and address_range.
	#partial switch Eh_Encoding_Flags(basic_encoding) {
	case .sdata4:
		one, two: i32
		read_i32(info, &one) or_return
		read_i32(info, &two) or_return
		fde.initial_location = i64(one)
		fde.address_range    = i64(two)

	case:
		fmt.panicf("unimplemented field encoding: %v", Eh_Encoding_Flags(basic_encoding))
	}

	#partial switch Eh_Encoding_Flags(encoding_modifier) {
	case .absptr:
		// Default.
	case .pcrel:
		// Start address is relative to the address of the initial_location field.
		fde.initial_location += i64(eh_frame.address + (u64(fde_off) - eh_frame.global_offset))
	case:
		fmt.panicf("unimplemented encoding modifier: %v", Eh_Encoding_Flags(encoding_modifier))
	}

	aug_offset := io.seek(info.reader, 0, .Current) or_return

	augment_length: u64
	read_uleb128(info, &augment_length) or_return
	fde.augmentation_bytes = make([]byte, augment_length, allocator) or_return
	io.read_full(info.reader, fde.augmentation_bytes) or_return

	lsda_pointer: Maybe(u64)
	if _, ok := cie.augmentations[.LSDA_Encoding].(u8); ok {
		#partial switch Eh_Encoding_Flags(basic_encoding) {
		case:
			fmt.panicf("unimplemented field encoding: %v", Eh_Encoding_Flags(basic_encoding))
		}

		#partial switch Eh_Encoding_Flags(encoding_modifier) {
		case .absptr:
			// Default.
		case .pcrel:
			lsda_pointer = lsda_pointer.? + eh_frame.address + (u64(aug_offset) - eh_frame.global_offset)
		case:
			fmt.panicf("unimplemented lsda encoding modifier: %v", Eh_Encoding_Flags(encoding_modifier))
		}
	}

	initial_length_size := u64(12 if hdr.format == .Bits_64 else 4)
	end_offset := off + hdr.length + initial_length_size
	fde.instructions = parse_instructions(info, end_offset, allocator) or_return
	return
}

parse_instructions :: proc(info: Info, end_offset: u64, allocator := context.allocator) -> (result: []Instruction, err: Error) {
	instructions := make([dynamic]Instruction, allocator)

	offset := io.seek(info.reader, 0, .Current) or_return
	instructions_loop: for offset < i64(end_offset) {
		PRIMARY_MASK     :: 0b11000000
		PRIMARY_ARG_MASK :: 0b00111111

		i: Instruction

		opcode := io.read_byte(info.reader) or_return

		primary     := opcode & PRIMARY_MASK
		primary_arg := opcode & PRIMARY_ARG_MASK

		primary_opcode := Call_Frame_Opcode(primary)
		#partial switch primary_opcode {
		case .advance_loc:
			i.opcode  = primary_opcode
			i.args[0] = primary_arg

		case .offset:
			i.opcode  = primary_opcode
			i.args[0] = primary_arg

			scnd: u64
			read_uleb128(info, &scnd) or_return
			i.args[1] = scnd

		case .restore:
			i.opcode  = primary_opcode
			i.args[0] = primary_arg

		case:
			i.opcode = Call_Frame_Opcode(opcode)
			#partial switch i.opcode {
			case .nop, .remember_state, .restore_state, .AARCH64_negate_ra_state:
			case .set_loc:
				val: u64
				// NOTE: is this the right address size to use here?
				read_target_address(info, u8(info.config.default_address_size), &val) or_return
				i.args[0] = val

			case .advance_loc1:
				i.args[0] = io.read_byte(info.reader) or_return

			case .advance_loc2:
				val: u16
				read_u16(info, &val) or_return
				i.args[0] = val

			case .advance_loc4:
				val: u32
				read_u32(info, &val) or_return
				i.args[0] = val

			case .offset_extended, .register, .def_cfa, .val_offset:
				one, two: u64
				read_uleb128(info, &one) or_return
				read_uleb128(info, &two) or_return
				i.args[0] = one
				i.args[1] = two

			case .restore_extended, .undefined, .same_value, .def_cfa_register, .def_cfa_offset:
				one: u64
				read_uleb128(info, &one) or_return
				i.args[0] = one

			case .def_cfa_offset_sf:
				one: i64
				read_sleb128(info, &one) or_return
				i.args[0] = one

			case .def_cfa_expression:
				length: u64
				read_uleb128(info, &length)            or_return
				parts := make([]u8, length, allocator) or_return
				io.read_full(info.reader, parts)       or_return
				i.args[0] = parts

			case .expression, .val_expression:
				one: u64
				read_uleb128(info, &one) or_return
				i.args[0] = one

				length: u64
				read_uleb128(info, &length)            or_return
				parts := make([]u8, length, allocator) or_return
				io.read_full(info.reader, parts)       or_return
				i.args[1] = parts

			case .offset_extended_sf, .def_cfa_sf, .val_offset_sf:
				one: u64
				read_uleb128(info, &one) or_return
				i.args[0] = one

				two: i64
				read_sleb128(info, &two) or_return
				i.args[1] = one

			case .GNU_args_size:
				one: u64
				read_uleb128(info, &one) or_return
				i.args[0] = one

			case:
				fmt.panicf("unknown CFI opcode: %v", i.opcode)
			}
		}

		append(&instructions, i)
		offset = io.seek(info.reader, 0, .Current) or_return
	}

	result = instructions[:]
	return
}

Instruction :: struct {
	opcode: Call_Frame_Opcode,
	args:   [2]Instruction_Arg,
}

Instruction_Arg :: union {
	u8,
	u16,
	u32,
	u64,
	i64,
	[]u8,
}

Call_Frame_Opcode :: enum u8 {
	advance_loc             = 0b01000000,
	offset                  = 0b10000000,
	restore                 = 0b11000000,
	nop                     = 0x00,
	set_loc                 = 0x01,
	advance_loc1            = 0x02,
	advance_loc2            = 0x03,
	advance_loc4            = 0x04,
	offset_extended         = 0x05,
	restore_extended        = 0x06,
	undefined               = 0x07,
	same_value              = 0x08,
	register                = 0x09,
	remember_state          = 0x0a,
	restore_state           = 0x0b,
	def_cfa                 = 0x0c,
	def_cfa_register        = 0x0d,
	def_cfa_offset          = 0x0e,
	def_cfa_expression      = 0x0f,
	expression              = 0x10,
	offset_extended_sf      = 0x11,
	def_cfa_sf              = 0x12,
	def_cfa_offset_sf       = 0x13,
	val_offset              = 0x14,
	val_offset_sf           = 0x15,
	val_expression          = 0x16,
	GNU_window_save         = 0x2d, // Used on SPARC, not in the corpus
	AARCH64_negate_ra_state = 0x2d,
	GNU_args_size           = 0x2e,
}

Eh_Encoding_Flags :: enum u8 {
	absptr  = 0x00,
	uleb128 = 0x01,
	udata2  = 0x02,
	udata4  = 0x03,
	udata8  = 0x04,

	signed  = 0x08,
	sleb128 = 0x09,
	sdata2  = 0x0a,
	sdata4  = 0x0b,
	sdata8  = 0x0c,

	pcrel    = 0x10,
	textrel  = 0x20,
	datarel  = 0x30,
	funcrel  = 0x40,
	aligned  = 0x50,
	indirect = 0x80,

	omit = 0xff,
}

CFI_Header :: struct {
	format:  Bits,
	length:  u64,
	cie_ptr: u64, // Is a CIE if 0, otherwise an FDE.
}

CIE :: struct {
	using header: CFI_Header,

	version:                 u8,
	augmentation:            string, // TODO: maybe just store the offset?
	code_alignment_factor:   u64,
	data_alignment_factor:   i64,
	return_address_register: u64,
	augmentations:           [Augmentation]Augmentation_Data,
	instructions:            []Instruction,
}

FDE :: struct {
	using header: CFI_Header,

	initial_location:   i64,
	address_range:      i64,
	augmentation_bytes: []byte,
	instructions:       []Instruction,
}

Augmentation :: enum {
	Length,
	LSDA_Encoding,
	FDE_Encoding,
	S,
	Personality,
}

Augmentation_Data :: union #no_nil {
	bool,
	u8,
	u64,
	i64,
}

Entry :: union #no_nil {
	Zero,
	CIE,
	FDE,
}

Zero :: struct {
	global_off: u64,
}
