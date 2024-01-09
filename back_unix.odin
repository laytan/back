//+build linux, darwin
package back

import "core:fmt"
import "core:os"
import "core:path/filepath"

PROGRAM := #config(BACK_PROGRAM, "")

@(init)
program_init :: proc() {
	if PROGRAM == "" {
		PROGRAM = os.args[0]
		if !filepath.is_abs(PROGRAM) {
			if abs, ok := filepath.abs(PROGRAM); ok {
				PROGRAM = abs
			} else {
				fmt.eprintln("back: could not convert `os.args[0]` to an absolute path")
			}
		}
	}
}
