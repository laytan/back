#+vet explicit-allocators
#+private
package back

@require import "base:runtime"

@require import "core:strings"

@require import "vendor/pdb/pdb"

_LINES_ERROR_FORK_LIMITED         :: 5
_LINES_ERROR_OUT_OF_MEMORY        :: 6
_LINES_ERROR_INVALID_FD           :: 7
_LINES_ERROR_PIPE_PROCESS_LIMITED :: 8
_LINES_ERROR_PIPE_SYSTEM_LIMITED  :: 9
_LINES_ERROR_FORK_NOT_SUPPORTED   :: 10

when !USE_FALLBACK {

_Trace_Entry :: pdb.StackFrame

_trace :: proc(buf: Trace) -> (n: int) {
	return int(pdb.capture_stack_trace(buf))
}

_lines_destroy :: proc(msgs: []Line, allocator: runtime.Allocator) {
	for msg in msgs {
		delete(msg.location, allocator)
		delete(msg.symbol, allocator)
	}
	delete(msgs, allocator)
}

_lines :: proc(bt: Trace, allocator, temp_allocator: runtime.Allocator) -> (out: []Line, err: Lines_Error) {
	// Debug info is needed, if we call pdb parser with out-of-date debug symbols it might panic to, so better to short-circuit right away.
	when !ODIN_DEBUG {
		return nil, .Info_Not_Found
	}

	context.allocator      = allocator
	context.temp_allocator = temp_allocator

	rb: pdb.RingBuffer(runtime.Source_Code_Location)
	pdb.init_rb(&rb, len(bt))
	defer delete(rb.data)

	{
		context.allocator = context.temp_allocator
		if pdb.parse_stack_trace(bt, true, &rb) {
			err = .Info_Not_Found
			return
		}
	}

	out = make([]Line, len(bt), allocator)
	for &msg, i in out {
		loc := pdb.get_rb(&rb, i)
		msg.symbol = strings.clone(loc.procedure, allocator)

		lb := strings.builder_make_len_cap(0, len(loc.file_path) + 5, allocator)
		strings.write_string(&lb, loc.file_path)
		strings.write_byte(&lb, ':')
		strings.write_int(&lb, int(loc.line))
		msg.location = strings.to_string(lb)
	}

	return
}

}
