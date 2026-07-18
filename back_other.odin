#+vet explicit-allocators
package back

@require import "base:runtime"

@require import "core:strings"

when USE_FALLBACK {

when ODIN_OPTIMIZATION_MODE == .None {
	#panic("the `back` package's `other` mode requires at least `-o:minimal` to work (it requires `#force_inline` to actually be applied)")
}

when ODIN_USE_SEPARATE_MODULES {
	#panic("the `back` package's `other` mode requires `-use-single-module` to work (there are subtle instrumentation bugs to hunt down)")
}

@(no_instrumentation)
other_instrumentation_enter :: #force_inline proc "contextless" (a, b: rawptr, loc: runtime.Source_Code_Location) {
	_other_instrumentation_enter(a, b, loc)
}

@(no_instrumentation)
other_instrumentation_exit :: #force_inline proc "contextless" (a, b: rawptr, loc: runtime.Source_Code_Location) {
	_other_instrumentation_exit(a, b, loc)
}

@(private="package")
_Trace_Entry :: runtime.Source_Code_Location

@(private="package")
_trace :: #force_no_inline proc(buf: Trace) -> (n: int) {
	lframe := frame

	// Omit this function's frame and the caller.
	if lframe != nil { lframe = lframe.prev }
	if lframe != nil { lframe = lframe.prev }

	for lframe != nil && n < len(buf) {
		buf[n] = lframe.loc

		n += 1
		lframe = lframe.prev
	}

	return
}

@(private="package")
_lines_destroy :: proc(lines: []Line, allocator: runtime.Allocator) {
	for line in lines {
		delete(line.location, allocator)
	}
}

@(private="package")
_lines :: proc(bt: Trace, allocator, temp_allocator: runtime.Allocator) -> (out: []Line, err: Lines_Error) {
	out = make([]Line, len(bt), allocator)

	for t, i in bt {
		out[i].symbol = t.procedure

		location := strings.builder_make(allocator)
		strings.write_string(&location, t.file_path)
		when ODIN_ERROR_POS_STYLE == .Default {
			strings.write_byte(&location, '(')
			strings.write_int (&location, int(t.line))
			if t.column != 0 {
				strings.write_byte(&location, ':')
				strings.write_int (&location, int(t.column))
			}
			strings.write_byte(&location, ')')
		} else when ODIN_ERROR_POS_STYLE == .Unix {
			strings.write_byte(&location, ':')
			strings.write_int (&location, int(t.line))
			if t.column != 0 {
				strings.write_byte(&location, ':')
				strings.write_int (&location, int(t.column))
			}
		} else {
			#panic("unhandled ODIN_ERROR_POS_STYLE")
		}

		out[i].location = strings.to_string(location)
	}

	return
}

@(private="file")
Frame :: struct {
    prev: ^Frame,
    loc:  runtime.Source_Code_Location,
}

@(thread_local, private="file")
frame: ^Frame

when OTHER_CUSTOM_INSTRUMENTATION {
	@(no_instrumentation, private="file")
	_other_instrumentation_enter :: #force_inline proc "contextless" (_, _: rawptr, loc: runtime.Source_Code_Location) {
		frame = &Frame{
			prev = frame,
			loc  = loc,
		}
	}

	@(no_instrumentation, private="file")
	_other_instrumentation_exit :: #force_inline proc "contextless" (_, _: rawptr, loc: runtime.Source_Code_Location) {
		frame = frame.prev
	}
} else {
	@(instrumentation_enter, private="file")
	_other_instrumentation_enter :: #force_inline proc "contextless" (_, _: rawptr, loc: runtime.Source_Code_Location) {
		frame = &Frame{
			prev = frame,
			loc  = loc,
		}
	}

	@(instrumentation_exit, private="file")
	_other_instrumentation_exit :: #force_inline proc "contextless" (_, _: rawptr, loc: runtime.Source_Code_Location) {
		frame = frame.prev
	}
}

}
