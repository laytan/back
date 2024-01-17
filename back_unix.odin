//+build linux, darwin
package back

import "core:c/libc"
import "core:fmt"
import "core:os"
import "core:runtime"

_register_segfault_handler :: proc() {
	libc.signal(libc.SIGSEGV, proc "c" (code: i32) {
		context = runtime.default_context()
		context.allocator = context.temp_allocator

		backtrace: {
			t := trace()
			lines, err := lines(t.trace[:t.len])
			if err != nil {
				fmt.eprintf("Exception (Code: %i)\nCould not get backtrace: %v\n", code, err)
				break backtrace
			}

			fmt.eprintf("Exception (Code: %i)\n[back trace]\n", code)
			print(lines)
		}

		os.exit(int(code))
	})
}
