//+private file
package back

import "core:strings"

foreign import system "system:System.framework"

// NOTE: CoreSymbolication is a private framework, Apple is allowed to break it and doesn't provide
// headers, although the API has as of my knowledge been the same in the past 10 years at least.
@(extra_linker_flags="-iframework /System/Library/PrivateFrameworks")
foreign import symbolication "system:CoreSymbolication.framework"

@(private="package")
_Trace_Entry :: rawptr

@(private="package")
_trace :: proc(buf: Trace) -> (n: int) {
	ctx:    unw_context_t
	cursor: unw_cursor_t

	assert(unw_getcontext(&ctx) == 0)
	assert(unw_init_local(&cursor, &ctx) == 0)

	pc: uintptr
	for ; unw_step(&cursor) > 0 && n < len(buf); n += 1 {
		assert(unw_get_reg(&cursor, .IP, &pc) == 0)
		buf[n] = rawptr(pc)
	}

	return
}

@(private="package")
_lines_destroy :: proc(lines: []Line) {
	for line in lines {
		delete(line.location)
		delete(line.symbol)
	}
	delete(lines)
}

@(private="package")
_lines :: proc(bt: Trace) -> (out: []Line, err: Lines_Error) {
	out = make([]Line, len(bt))

	symbolicator := CSSymbolicatorCreateWithPid(getpid())
	defer CSRelease(symbolicator)

	for &msg, i in out {
		symbol := CSSymbolicatorGetSymbolWithAddressAtTime(symbolicator, uintptr(bt[i]), CSNow)
		info   := CSSymbolicatorGetSourceInfoWithAddressAtTime(symbolicator, uintptr(bt[i]), CSNow)

		msg.symbol = strings.clone_from(CSSymbolGetName(symbol))

		// No debug info.
		if CSIsNull(info) {
			owner := CSSymbolGetSymbolOwner(symbol)
			msg.location = strings.clone_from(CSSymbolOwnerGetPath(owner))
		} else {
			path := string(CSSourceInfoGetPath(info))
			location := strings.builder_make(0, len(path)+6)
			strings.write_string(&location, path)
			strings.write_string(&location, ":")
			strings.write_int(&location, int(CSSourceInfoGetLineNumber(info)))
			msg.location = strings.to_string(location)
		}
	}
	return
}

CSTypeRef :: struct {
	csCppData: rawptr,
	csCppObj:  rawptr,
}

CSSymbolicatorRef :: distinct CSTypeRef
CSSymbolRef       :: distinct CSTypeRef
CSSourceInfoRef   :: distinct CSTypeRef
CSSymbolOwnerRef  :: distinct CSTypeRef

CSNow :: 0x80000000

foreign symbolication {
	@(link_name="CSIsNull")
	_CSIsNull :: proc(ref: CSTypeRef) -> bool ---
	@(link_name="CSRelease")
	_CSRelease :: proc(ref: CSTypeRef) ---

	CSSymbolicatorCreateWithPid :: proc(pid: pid_t) -> CSSymbolicatorRef ---

	CSSymbolicatorGetSymbolWithAddressAtTime     :: proc(symbolicator: CSSymbolicatorRef, addr: uintptr, time: u64) -> CSSymbolRef ---
	CSSymbolicatorGetSourceInfoWithAddressAtTime :: proc(symbolicator: CSSymbolicatorRef, adrr: uintptr, time: u64) -> CSSourceInfoRef ---

	CSSymbolGetName        :: proc(symbol: CSSymbolRef) -> cstring ---
	CSSymbolGetSymbolOwner :: proc(symbol: CSSymbolRef) -> CSSymbolOwnerRef ---

	CSSourceInfoGetPath       :: proc(info: CSSourceInfoRef) -> cstring ---
	CSSourceInfoGetLineNumber :: proc(info: CSSourceInfoRef) -> i32 ---
	CSSourceInfoGetSymbol     :: proc(info: CSSourceInfoRef) -> CSSymbolRef ---

	CSSymbolOwnerGetPath :: proc(owner: CSSymbolOwnerRef) -> cstring ---
}

CSRelease :: #force_inline proc(ref: $T) {
	_CSRelease(CSTypeRef(ref))
}

CSIsNull :: #force_inline proc(ref: $T) -> bool {
	return _CSIsNull(CSTypeRef(ref))
}

// These could actually be smaller, but then we would have to define and check the size on each
// architecture, the sizes here are the largest they can be.
_LIBUNWIND_CONTEXT_SIZE :: 167
_LIBUNWIND_CURSOR_SIZE :: 204

unw_context_t :: struct {
	data: [_LIBUNWIND_CONTEXT_SIZE]u64,
}

unw_cursor_t :: struct {
	data: [_LIBUNWIND_CURSOR_SIZE]u64,
}

// Cross-platform registers, each architecture has additional registers but these are enough for us.
Register :: enum i32 {
	SP = -2,
	IP = -1,
}

pid_t :: distinct i32

foreign system {
	unw_getcontext :: proc(ctx: ^unw_context_t) -> i32 ---
	unw_init_local :: proc(cursor: ^unw_cursor_t, ctx: ^unw_context_t) -> i32 ---
	unw_get_reg    :: proc(cursor: ^unw_cursor_t, name: Register, reg: ^uintptr) -> i32 ---
	unw_step       :: proc(cursor: ^unw_cursor_t) -> i32 ---

	getpid :: proc() -> pid_t ---
}
