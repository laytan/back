package back

@require import "base:runtime"

@require import "core:fmt"

when USE_FALLBACK {

when ODIN_OPTIMIZATION_MODE == .None {
	#panic("the `back` package's `other` mode requires at least `-o:minimal` to work (it requires `#force_inline` to actually be applied)")
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
_trace :: proc(buf: Trace) -> (n: int) {
	lframe := frame
	for lframe != nil && n < len(buf) {
		buf[n] = lframe.loc

		n += 1
		lframe = lframe.prev
	}

	return
}

@(private="package")
_lines_destroy :: proc(lines: []Line) {
	for line in lines {
		delete(line.location)
	}
}

@(private="package")
_lines :: proc(bt: Trace) -> (out: []Line, err: Lines_Error) {
	out = make([]Line, len(bt))

	for t, i in bt {
		out[i].symbol = t.procedure
		out[i].location = fmt.aprintf("%s(%v:%v)", t.file_path, t.line, t.column)
	}

	return
}

when ODIN_OS != .Linux && ODIN_OS != .Darwin {
	@(private="package")
	_register_segfault_handler :: proc() {}
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
