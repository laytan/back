package dwarf

// foreign import registers "registers.o"
// foreign registers {
// 	@(link_name="registers_current")
// 	_registers_current :: proc(rip, rsp, rbp: ^u64) ---
// }
//
// registers_current :: #force_inline proc(regs: ^Registers) {
// 	_registers_current((^u64)(&regs.rip), (^u64)(&regs.rsp), (^u64)(&regs.rbp))
// 	(^i64)(uintptr(&regs.rip) + 8)^ = 1
// 	(^i64)(uintptr(&regs.rsp) + 8)^ = 1
// 	(^i64)(uintptr(&regs.rbp) + 8)^ = 1
// }

foreign import registers "registers.asm"
foreign registers {
	registers_current :: proc(regs: ^Registers) ---
}

Registers :: struct {
	rip: Maybe(u64), // Instruction pointer.
	rsp: Maybe(u64), // Stack pointer.
	rbp: Maybe(u64), // Base pointer.
	ret: Maybe(u64), // Return address.
}

Call_Frame :: struct {
	pc: u64,
}

// Arch dependent.
Register_Mapping :: enum u8 {
	RAX,
	RDX,
	RCX,
	RBX,
	RSI,
	RDI,
	RBP,

	RSP, // 7.

	R8,
	R9,
	R10,
	R11,
	R12,
	R13,
	R14,
	R15,

	RA, // 16.

	XMM0,
	XMM1,
	XMM2,
	XMM3,
	XMM4,
	XMM5,
	XMM6,
	XMM7,
	XMM8,
	XMM9,
	XMM10,
	XMM11,
	XMM12,
	XMM13,
	XMM14,
	XMM15,

	ST0,
	ST1,
	ST2,
	ST3,
	ST4,
	ST5,
	ST6,
	ST7,

	MM0,
	MM1,
	MM2,
	MM3,
	MM4,
	MM5,
	MM6,
	MM7,

	RFLAGS,

	ES,
	CS,
	SS,
	DS,
	FS,
	GS,

	FS_Base = 58,
	GS_Base,

	TR = 62,
	LDTR,
	MXCSR,
	FCW,
	FSW,

	XMM16,
	XMM17,
	XMM18,
	XMM19,
	XMM20,
	XMM21,
	XMM22,
	XMM23,
	XMM24,
	XMM25,
	XMM26,
	XMM27,
	XMM28,
	XMM29,
	XMM30,
	XMM31,

	K0 = 118,
	K1,
	K2,
	K3,
	K4,
	K5,
	K6,
	K7,
}

Unwind_Error :: enum {
	OK,
	No_PC_Register,
}

Unwinder :: struct {
	info:      ^Info,
	registers: Registers,
	is_first:  bool,
	cfa: u64,
}

unwinder_init :: proc(u: ^Unwinder, info: ^Info, start: Registers) {
	u.registers = start
	u.is_first  = true
	u.info = info
}

unwinder_next :: proc(u: ^Unwinder, allocator := context.temp_allocator) -> (cf: Call_Frame, err: Error) {
	pc, has_pc := u.registers.rip.?
	if !has_pc { return {}, .No_PC_Register }

	if u.is_first {
		u.is_first = false
		return { pc }, nil
	}

	row := unwind_info_for_address(u.info, pc, allocator) or_return
	if row == nil {
		return
	}

	switch cfa in row.cfa {
	case Register_And_Offset:
		val: u64
		#partial switch cfa.register {
		case .RSP: val = u.registers.rsp.?
		case .RA:  val = u.registers.ret.?
		case .RBP: val = u.registers.rbp.?
		case:      panic("unknown register")
		}
		u.cfa = val + cfa.offset
	case Expression:
		panic("don't support expression cfa")
	case:
		panic("no cfa rule")
	}

	for reg in ([]Register_Mapping{.RSP, .RBP, .RA}) {
		#partial switch rule in row.registers[reg] {
		case Undefined:
			#partial switch reg {
			case .RSP: u.registers.rsp = nil
			case .RA:  u.registers.ret = nil
			case .RBP: u.registers.rbp = nil
			case: unreachable()
			}
		case Same_Value:
		case Offset:
			// TODO: no way this is correct.
			ptr := cast(^uint)uintptr(u64(i64(u.cfa) + i64(rule)))
			#partial switch reg {
			case .RSP: u.registers.rsp = u64(ptr^)
			case .RA:  u.registers.ret = u64(ptr^)
			case .RBP: u.registers.rbp = u64(ptr^)
			case: unreachable()
			}
		case:
			panic("unimplemented register rule")
		}
	}

	ret := u.registers.ret.?
	u.registers.rip = ret
	u.registers.rsp = u.cfa

	return { ret }, nil
}

unwind_info_for_address :: proc(info: ^Info, address: u64, allocator := context.allocator) -> (row: ^Row, err: Error) {
	entries := call_frame_info(info^, allocator) or_return

	cie: CIE
	for entry in entries {
		switch et in entry {
		case CIE:
			cie = et

		case FDE:
			start := u64(et.initial_location)
			end   := start + u64(et.address_range)

			if start <= address && address <= end {
				// TODO: probably not always the case where the fde's cie is the first one before the fde?
				table := unwind_table_for_fde(info, cie, et) or_return
				for {
					row = unwind_table_next_row(&table) or_return
					if row == nil {
						break
					}
					if address >= row.start_address && address <= row.end_address {
						return
					}
				}
			}

		case Zero:
		}
	}

	return
}

CFA :: union {
	Register_And_Offset,
	Expression,
}

Register_And_Offset :: struct {
	register: Register_Mapping,
	offset:   u64,
}

Expression :: distinct []byte

Register_Rule :: union #no_nil {
	Undefined,
	Same_Value,
	Offset,
	Val_Offset,
	Register,
	Expression,
	Val_Expression,
}

Undefined      :: distinct struct{}
Same_Value     :: distinct struct{}
Offset         :: distinct i64
Val_Offset     :: distinct i64
Register       :: distinct Register_Mapping
Val_Expression :: distinct Expression

Row :: struct {
	start_address: u64,
	end_address:   u64,
	cfa:           CFA,
	registers:     #sparse[Register_Mapping]Register_Rule,
	is_default:    bool,
}

import sa "core:container/small_array"

Unwind_Context :: struct {
	stack:          sa.Small_Array(8, Row),
	initial_rule:   Maybe(Initial_Rule),
	is_initialized: bool,
}

unwind_context_init :: proc(self: ^Unwind_Context, info: ^Info, cie: CIE) -> Error {
	unwind_context_reset(self)

	table := unwind_table_for_cie(self^, cie)
	for {
		row := unwind_table_next_row(&table) or_return
		if row == nil { break }
	}

	unwind_context_save_initial_rules(self)
	// TODO: IEIEEIEIEIWWWH
	self^ = table.ctx
	return nil
}

unwind_context_save_initial_rules :: proc(self: ^Unwind_Context) {
	self.is_initialized = true

	// TODO: implement.
}

unwind_context_reset :: proc(c: ^Unwind_Context) {
	sa.clear(&c.stack)
	sa.push(&c.stack, Row{ is_default = true })

	c.initial_rule   = nil
	c.is_initialized = false
}

unwind_context_row :: proc(self: ^Unwind_Context) -> ^Row {
	return sa.get_ptr(&self.stack, sa.len(self.stack)-1)
}

unwind_context_set_start_address :: proc(self: ^Unwind_Context, start_address: u64) {
	row := unwind_context_row(self)
	row.start_address = start_address
}

unwind_context_start_address :: proc(self: ^Unwind_Context) -> u64 {
	row := unwind_context_row(self)
	return row.start_address
}

unwind_context_set_cfa :: proc(self: ^Unwind_Context, cfa: CFA) {
	row := unwind_context_row(self)
	row.cfa = cfa
}

unwind_context_cfa :: proc(self: ^Unwind_Context) -> ^CFA {
	return &unwind_context_row(self).cfa
}

Initial_Rule :: struct {
	register: Register_Mapping,
	rule:     Register_Rule,
}

Unwind_Table :: struct {
	code_alignment_factor: u64,
	data_alignment_factor: i64,
	next_start_address:    u64,
	last_end_address:      u64,
	returned_last_row:     bool,
	current_row_valid:     bool,
	instructions:          []Instruction,
	ctx:                   Unwind_Context,
}

unwind_table_for_cie :: proc(ctx: Unwind_Context, cie: CIE) -> Unwind_Table {
	return Unwind_Table{
		code_alignment_factor = cie.code_alignment_factor,
		data_alignment_factor = cie.data_alignment_factor,
		instructions          = cie.instructions,
		ctx                   = ctx,
	}
}

unwind_table_for_fde :: proc(info: ^Info, cie: CIE, fde: FDE) -> (tbl: Unwind_Table, err: Error) {
	assert(fde.initial_location > 0)
	assert(fde.initial_location + fde.address_range > 0)
	tbl = {
		code_alignment_factor = cie.code_alignment_factor,
		data_alignment_factor = cie.data_alignment_factor,
		next_start_address    = u64(fde.initial_location),
		last_end_address      = u64(fde.initial_location + fde.address_range),
		instructions          = fde.instructions,
	}
	unwind_context_init(&tbl.ctx, info, cie) or_return
	return
}

unwind_table_next_row :: proc(self: ^Unwind_Table, loc := #caller_location) -> (row: ^Row, err: Error) {
	unwind_context_set_start_address(&self.ctx, self.next_start_address)
	self.current_row_valid = false

	for {
		if len(self.instructions) == 0 {
			if self.returned_last_row {
				return
			}

			row = unwind_context_row(&self.ctx)
			row.end_address = self.last_end_address

			self.returned_last_row = true
			self.current_row_valid = true
			return
		}

		instruction := self.instructions[0]
		defer self.instructions = self.instructions[1:]

		if unwind_table_evaluate(self, instruction) or_return {
			self.current_row_valid = true
			row = unwind_context_row(&self.ctx)
			return
		}
	}
}

unwind_table_evaluate :: proc(self: ^Unwind_Table, instr: Instruction) -> (row_done: bool, err: Error) {
	switch instr.opcode {
	// Instructions that complete the current row and advance the address for the next row.
	case .set_loc:
		address := instr.args[0]

		self.next_start_address = address.(u64)
		unwind_context_row(&self.ctx).end_address = self.next_start_address

		row_done = true
		return

	case .advance_loc, .advance_loc1:
		delta := u64(instr.args[0].(u8)) * self.code_alignment_factor

		self.next_start_address = unwind_context_start_address(&self.ctx) + delta
		unwind_context_row(&self.ctx).end_address = self.next_start_address

		row_done = true
		return

	// case .advance_loc1:
	// 	delta := u64(instr.args[0].(u8)) * self.code_alignment_factor
	//
	// 	self.next_start_address = unwind_context_start_address(&self.ctx) + delta
	// 	unwind_context_row(&self.ctx).end_address = self.next_start_address
	//
	// 	row_done = true
	// 	return

	case .advance_loc2:
		delta := u64(instr.args[0].(u16)) * self.code_alignment_factor

		self.next_start_address = unwind_context_start_address(&self.ctx) + delta
		unwind_context_row(&self.ctx).end_address = self.next_start_address

		row_done = true
		return

	case .advance_loc4:
		delta := u64(instr.args[0].(u64)) * self.code_alignment_factor

		self.next_start_address = unwind_context_start_address(&self.ctx) + delta
		unwind_context_row(&self.ctx).end_address = self.next_start_address

		row_done = true
		return

	// Instructions that modify the CFA.
	case .def_cfa:
		register := instr.args[0].(u64)
		offset   := instr.args[1].(u64)

		unwind_context_set_cfa(&self.ctx, Register_And_Offset{ Register_Mapping(register), offset })
		return

	case .def_cfa_sf:
		register        := instr.args[0].(u8)
		factored_offset := instr.args[1].(i64)

		new_offset := factored_offset * self.data_alignment_factor
		assert(new_offset > 0)
		unwind_context_set_cfa(&self.ctx, Register_And_Offset{
			Register_Mapping(register),
			u64(new_offset),
		})
		return

	case .def_cfa_register:
		register := instr.args[0].(u64)

		reg_off := &unwind_context_cfa(&self.ctx).(Register_And_Offset)
		reg_off.register = Register_Mapping(register)
		return

	case .def_cfa_offset:
		offset := instr.args[0].(u64)

		reg_off := &unwind_context_cfa(&self.ctx).(Register_And_Offset)
		reg_off.offset = offset
		return

	case .def_cfa_offset_sf:
		factored_offset := instr.args[0].(i64)

		new_offset := factored_offset * self.data_alignment_factor
		assert(new_offset > 0)

		reg_off := &unwind_context_cfa(&self.ctx).(Register_And_Offset)
		reg_off.offset = u64(new_offset)
		return

	case .def_cfa_expression:
		expression := instr.args[0].([]u8)

		unwind_context_set_cfa(&self.ctx, Expression(expression))
		return

	// Instructions that define register rules.
	case .undefined:
		register := instr.args[0].(u8)

		row := unwind_context_row(&self.ctx)
		row.registers[Register_Mapping(register)] = Undefined{}
		return

	case .same_value:
		register := instr.args[0].(u8)

		row := unwind_context_row(&self.ctx)
		row.registers[Register_Mapping(register)] = Same_Value{}
		return

	case .offset, .offset_extended:
		register        := instr.args[0].(u8)
		factored_offset := instr.args[1].(u64)


		offset := i64(factored_offset) * self.data_alignment_factor
		row := unwind_context_row(&self.ctx)
		row.registers[Register_Mapping(register)] = Offset(offset)
		return

	case .offset_extended_sf:
		register        := instr.args[0].(u8)
		factored_offset := instr.args[1].(i64)

		offset := factored_offset * self.data_alignment_factor
		row := unwind_context_row(&self.ctx)
		row.registers[Register_Mapping(register)] = Offset(offset)
		return

	case .val_offset:
		register        := instr.args[0].(u8)
		factored_offset := instr.args[1].(u64)

		offset := i64(factored_offset) * self.data_alignment_factor
		row := unwind_context_row(&self.ctx)
		row.registers[Register_Mapping(register)] = Val_Offset(offset)
		return

	case .val_offset_sf:
		register        := instr.args[0].(u8)
		factored_offset := instr.args[1].(i64)

		offset := factored_offset * self.data_alignment_factor
		row := unwind_context_row(&self.ctx)
		row.registers[Register_Mapping(register)] = Val_Offset(offset)
		return

	case .register:
		dest := instr.args[0].(u8)
		src  := instr.args[1].(u8)

		row := unwind_context_row(&self.ctx)
		row.registers[Register_Mapping(dest)] = row.registers[Register_Mapping(src)]
		return

	case .expression:
		register   := instr.args[0].(u8)
		expression := instr.args[1].([]u8)

		row := unwind_context_row(&self.ctx)
		row.registers[Register_Mapping(register)] = Expression(expression)
		return

	case .val_expression:
		register   := instr.args[0].(u8)
		expression := instr.args[1].([]u8)

		row := unwind_context_row(&self.ctx)
		row.registers[Register_Mapping(register)] = Val_Expression(expression)
		return

	case .restore, .restore_extended:
		panic("unimplemented: .restore, .restore_extended")

	// Row push and pop instructions.
	case .remember_state:
		panic("unimplemented: .remember_state")
	case .restore_state:
		panic("unimplemented: .restore_state")

	// GNU Extension. Save the size somewhere so the unwinder can use it when restoring IP.
	case .GNU_args_size:
		panic("unimplemented: .GNU_args_size")

	// AArch64 extension.
	case .AARCH64_negate_ra_state:
		panic("unimplemented: .AARCH64_negate_ra_state")

	// No operation.
	case .nop:
		return

	case:
		panic("unknown opcode in instruction")
	}
}

