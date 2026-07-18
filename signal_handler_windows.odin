#+vet explicit-allocators
package back

import     "base:runtime"

import     "core:fmt"
import     "core:mem"
import     "core:strings"
import win "core:sys/windows"

import     "vendor/pdb/pdb"

_register_segfault_handler :: proc() {
	pdb.SetUnhandledExceptionFilter(proc "stdcall" (exception_info: ^win.EXCEPTION_POINTERS) -> win.LONG {
		context = runtime.default_context()

		space: [16*mem.Kilobyte]byte
		arena: mem.Arena
		mem.arena_init(&arena, space[:])
		allocator := mem.arena_allocator(&arena)

		context.allocator      = allocator
		context.temp_allocator = allocator

		fmt.eprint("Exception ")
		if exception_info.ExceptionRecord != nil {
			fmt.eprintf("(Type: %x, Flags: %x)\n", exception_info.ExceptionRecord.ExceptionCode, exception_info.ExceptionRecord.ExceptionFlags)
		}

		when USE_FALLBACK {
			lines, err := lines(trace(), allocator)
			if err != nil {
				fmt.eprintln("Could not get backtrace: %v", err)
				return win.EXCEPTION_CONTINUE_SEARCH
			}

			fmt.eprintln("[back trace]")
			print(lines, temp_allocator=allocator)
		} else {
			ctxt := cast(^pdb.CONTEXT)exception_info.ContextRecord

			trace_buf: [BACKTRACE_SIZE]pdb.StackFrame
			trace_count := pdb.capture_stack_trace_from_context(ctxt, trace_buf[:])

			src_code_locs: pdb.RingBuffer(runtime.Source_Code_Location)
			pdb.init_rb(&src_code_locs, BACKTRACE_SIZE, allocator)

			no_debug_info_found := pdb.parse_stack_trace(trace_buf[:trace_count], true, &src_code_locs)
			if no_debug_info_found {
				fmt.eprintln("Could not get backtrace: pdb file not found, compile with `-debug` to generate pdb files and get a back trace.")
				return win.EXCEPTION_CONTINUE_SEARCH
			}

			fmt.eprintln("[back trace]")

			lines: [BACKTRACE_SIZE]Line
			for i in 0..<src_code_locs.len {
				loc := pdb.get_rb(&src_code_locs, i)

				lb := strings.builder_make_len_cap(0, len(loc.file_path) + 5, allocator)
				strings.write_string(&lb, loc.file_path)
				strings.write_byte(&lb, ':')
				strings.write_int(&lb, int(loc.line))

				lines[i] = {
					location = strings.to_string(lb),
					symbol   = loc.procedure,
				}
			}
			print(lines[:src_code_locs.len], temp_allocator=allocator)
		}

		return win.EXCEPTION_CONTINUE_SEARCH
	})
}
