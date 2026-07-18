#+vet explicit-allocators
#+build linux, darwin, netbsd, openbsd, freebsd
package back

import "base:runtime"

import "core:fmt"
import "core:mem"
import "core:sys/posix"

@(private="package")
_register_segfault_handler :: proc() {
	posix.signal(.SIGSEGV, proc "c" (code: posix.Signal) {
		context = runtime.default_context()

		space: [16*mem.Kilobyte]byte
		arena: mem.Arena
		mem.arena_init(&arena, space[:])
		allocator := mem.arena_allocator(&arena)

		context.allocator      = allocator
		context.temp_allocator = allocator

		backtrace: {
			lines, err := lines(trace(), allocator, allocator)
			if err != nil {
				fmt.eprintf("Exception (Code: %i)\nCould not get backtrace: %v\n", code, err)
				break backtrace
			}

			fmt.eprintf("Exception (Code: %i)\n[back trace]\n", code)
			print(lines, temp_allocator=allocator)
		}

		runtime.exit(int(code))
	})
}
