#+vet explicit-allocators
#+private
package back

@require import "base:intrinsics"
@require import "base:runtime"

@require import     "core:strings"
@require import     "core:sync"
@require import win "core:sys/windows"

when !USE_FALLBACK {

_Trace_Entry :: uintptr

_trace :: #force_no_inline proc(buf: Trace) -> (n: int) {
	frame_count := win.RtlCaptureStackBackTrace(2, u32(len(buf)), ([^]rawptr)(raw_data(buf)), nil)

	for &frame in buf[:frame_count] {
		// NOTE: Return address is one after the call instruction so subtract a byte to
		// end up back inside the call instruction which is needed for SymFromAddr.
		frame -= 1
	}

	return int(frame_count)
}

_lines_destroy :: proc(lines: []Line, allocator: runtime.Allocator) {
	for line in lines {
		delete(line.location, allocator)
		if line.symbol != "??" && line.symbol != "??OOM" {
			delete(line.symbol, allocator)
		}
	}
	delete(lines, allocator)
}

_lines :: proc(bt: Trace, allocator, temp_allocator: runtime.Allocator) -> (out: []Line, err: Lines_Error) {
	// Debug info is needed, if we call with out-of-date debug symbols it will return out-of-date info, so better to short-circuit right away.
	when !ODIN_DEBUG {
		out = make([]Line, len(bt), allocator)
		for &line, i in out {
			line.symbol = "??"

			location := strings.builder_make(allocator)
			strings.write_string(&location, "0x")
			strings.write_i64   (&location, i64(bt[i]), 16)
			line.location = strings.to_string(location)
		}

		return
	}

	out = make([]Line, len(bt), allocator)
	defer if err != nil { _lines_destroy(out, allocator) }

	process := win.GetCurrentProcess()

	sync.guard(&_win32_dbghelp_mutex)

	win.SymSetOptions(win.SYMOPT_LOAD_LINES|win.SYMOPT_DEFERRED_LOADS)
	if !win.SymInitializeW(process, nil, true) {
		err = .Info_Not_Found
		return
	}
	defer win.SymCleanup(process)

	win.SymSetOptions(win.SYMOPT_LOAD_LINES|win.SYMOPT_DEFERRED_LOADS)

	data: [size_of(win.SYMBOL_INFOW) + size_of([256]win.WCHAR)]byte
	symbol := (^win.SYMBOL_INFOW)(&data[0])
	// The value of SizeOfStruct must be the size of the whole struct,
	// not just the size of the pointer
	symbol.SizeOfStruct = size_of(symbol^)
	symbol.MaxNameLen = 255

	for &line, i in out {
		if win.SymFromAddrW(process, win.DWORD64(bt[i]), nil, symbol) {
			symbol, mem_err := win.wstring_to_utf8(cstring16(&symbol.Name[0]), int(symbol.NameLen), allocator)
			if mem_err != nil {
				line.symbol = "??OOM"
			} else if symbol == "??" {
				delete(symbol, allocator)
				line.symbol = "??"
			} else {
				line.symbol = symbol
			}
		} else {
			line.symbol = "??"
		}

		lineInfo: win.IMAGEHLP_LINE64
		lineInfo.SizeOfStruct = size_of(lineInfo)
		if win.SymGetLineFromAddrW64(process, win.DWORD64(bt[i]), &{}, &lineInfo) {
			location := strings.builder_make(allocator)
			strings.write_string16(&location, string16(lineInfo.FileName))
			when ODIN_ERROR_POS_STYLE == .Default {
				strings.write_byte(&location, '(')
				strings.write_int (&location, int(lineInfo.LineNumber))
				strings.write_byte(&location, ')')
			} else when ODIN_ERROR_POS_STYLE == .Unix {
				strings.write_byte(&location, ':')
				strings.write_int (&location, int(lineInfo.LineNumber))
			} else {
				#panic("unhandled ODIN_ERROR_POS_STYLE")
			}
			line.location = strings.to_string(location)
		} else {
			location := strings.builder_make(allocator)
			strings.write_string(&location, "0x")
			strings.write_i64   (&location, i64(bt[i]), 16)
			line.location = strings.to_string(location)
		}
	}

	return
}

}
