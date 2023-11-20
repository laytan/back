//+private
package obacktracing

import "core:runtime"
import "core:strings"

import "vendor/pdb/pdb"

_Backtrace :: []pdb.StackFrame

_backtrace_get :: proc(max_len: i32, allocator := context.allocator) -> Backtrace {
	buf := make(Backtrace, max_len, allocator)

	context.allocator = context.temp_allocator
	size := pdb.capture_stack_trace(buf)
	return buf[:size]
}

_backtrace_delete :: proc(bt: Backtrace) {
	delete(bt)
}

_backtrace_messages :: proc(bt: Backtrace, allocator := context.allocator) -> (out: []Message, err: Message_Error) {
	context.allocator = allocator

	// Debug info is needed, if we call pdb parser with out-of-date debug symbols it might panic to, so better to short-circuit right away.
	when !ODIN_DEBUG {
		return nil, .Info_Not_Found
	}

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

	out = make([]Message, len(bt))
	for &msg, i in out {
		loc := pdb.get_rb(&rb, i)
		msg.symbol = strings.clone(loc.procedure)

		lb := strings.builder_make_len_cap(0, len(loc.file_path) + 5)
		strings.write_string(&lb, loc.file_path)
		strings.write_byte(&lb, ':')
		strings.write_int(&lb, int(loc.line))
		msg.location = strings.to_string(lb)
	}

	return
}
