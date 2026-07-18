#+vet explicit-allocators
package back

import     "base:runtime"

import     "core:fmt"
import     "core:mem"
import win "core:sys/windows"

_register_segfault_handler :: proc() {
	win.SetUnhandledExceptionFilter(proc "stdcall" (exception_info: ^win.EXCEPTION_POINTERS) -> win.LONG {
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

		lines, err := lines(trace(), allocator, allocator)
		if err != nil {
			fmt.eprintln("Could not get backtrace: %v", err)
			return win.EXCEPTION_CONTINUE_SEARCH
		}

		fmt.eprintln("[back trace]")
		print(lines, temp_allocator=allocator)

		return win.EXCEPTION_CONTINUE_SEARCH
	})
}
