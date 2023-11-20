package obacktracing

import "core:fmt"
import "core:mem"
import "core:os"
import "core:runtime"
import "core:sync"
import "core:thread"

// The backtrace tracking allocator is the same allocator as the core tracking allocator but keeps
// backtraces for each allocation.
//
// See examples/allocator for a usage snippet.
//
// Print results at the end using tracking_allocator_print_results().
Tracking_Allocator :: struct {
	backing:              mem.Allocator,
	internals_allocator:  mem.Allocator,
	allocation_map:       map[rawptr]Tracking_Allocator_Entry,
	bad_free_array:       [dynamic]Tracking_Allocator_Bad_Free_Entry,
	mutex:                sync.Mutex,
	clear_on_free_all:    bool,
}

Tracking_Allocator_Entry :: struct {
	memory:    rawptr,
	size:      int,
	alignment: int,
	mode:      mem.Allocator_Mode,
	err:       mem.Allocator_Error,
	location:  runtime.Source_Code_Location,
	backtrace: Backtrace,
}

Tracking_Allocator_Bad_Free_Entry :: struct {
	memory:    rawptr,
	location:  runtime.Source_Code_Location,
	backtrace: Backtrace,
}

tracking_allocator_init :: proc(
	t: ^Tracking_Allocator,
	backing_allocator: mem.Allocator,
	internals_allocator := context.allocator,
) {
	t.backing = backing_allocator
	t.internals_allocator = internals_allocator
	t.allocation_map.allocator = internals_allocator
	t.bad_free_array.allocator = internals_allocator

	if .Free_All in mem.query_features(t.backing) {
		t.clear_on_free_all = true
	}
}

tracking_allocator_destroy :: proc(t: ^Tracking_Allocator) {
	for _, leak in t.allocation_map do backtrace_delete(leak.backtrace)
	delete(t.allocation_map)

	for bad_free in t.bad_free_array do backtrace_delete(bad_free.backtrace)
	delete(t.bad_free_array)
}

tracking_allocator_clear :: proc(t: ^Tracking_Allocator) {
	sync.guard(&t.mutex)

	for _, leak in t.allocation_map do backtrace_delete(leak.backtrace)
	clear(&t.allocation_map)

	for bad_free in t.bad_free_array do backtrace_delete(bad_free.backtrace)
	clear(&t.bad_free_array)
}

@(require_results)
tracking_allocator :: proc(data: ^Tracking_Allocator) -> mem.Allocator {
	return mem.Allocator{data = data, procedure = tracking_allocator_proc}
}

tracking_allocator_proc :: proc(
	allocator_data: rawptr,
	mode: mem.Allocator_Mode,
	size, alignment: int,
	old_memory: rawptr,
	old_size: int,
	loc := #caller_location,
) -> (
	result: []byte,
	err: mem.Allocator_Error,
) {
	data := (^Tracking_Allocator)(allocator_data)

	sync.mutex_guard(&data.mutex)

	if mode == .Query_Info {
		info := (^mem.Allocator_Query_Info)(old_memory)
		if info != nil && info.pointer != nil {
			if entry, ok := data.allocation_map[info.pointer]; ok {
				info.size = entry.size
				info.alignment = entry.alignment
			}
			info.pointer = nil
		}

		return
	}

	if mode == .Free && old_memory != nil && old_memory not_in data.allocation_map {
		append(
			&data.bad_free_array,
			Tracking_Allocator_Bad_Free_Entry{
				memory = old_memory,
				location = loc,
				backtrace = backtrace_get(BACKTRACE_SIZE, data.internals_allocator),
			},
		)
	} else {
		result = data.backing.procedure(
			data.backing.data,
			mode,
			size,
			alignment,
			old_memory,
			old_size,
			loc,
		) or_return
	}
	result_ptr := raw_data(result)

	if data.allocation_map.allocator.procedure == nil {
		data.allocation_map.allocator = context.allocator
	}

	switch mode {
	case .Alloc, .Alloc_Non_Zeroed:
		data.allocation_map[result_ptr] = Tracking_Allocator_Entry {
			memory    = result_ptr,
			size      = size,
			mode      = mode,
			alignment = alignment,
			err       = err,
			location  = loc,
			backtrace = backtrace_get(BACKTRACE_SIZE, data.internals_allocator),
		}
	case .Free:
		delete_key(&data.allocation_map, old_memory)
	case .Free_All:
		if data.clear_on_free_all {
			clear_map(&data.allocation_map)
		}
	case .Resize:
		if old_memory != result_ptr {
			delete_key(&data.allocation_map, old_memory)
		}
		data.allocation_map[result_ptr] = Tracking_Allocator_Entry {
			memory    = result_ptr,
			size      = size,
			mode      = mode,
			alignment = alignment,
			err       = err,
			location  = loc,
			backtrace = backtrace_get(BACKTRACE_SIZE, data.internals_allocator),
		}

	case .Query_Features:
		set := (^mem.Allocator_Mode_Set)(old_memory)
		if set != nil {
			set^ = {
				.Alloc,
				.Alloc_Non_Zeroed,
				.Free,
				.Free_All,
				.Resize,
				.Query_Features,
				.Query_Info,
			}
		}
		return nil, nil

	case .Query_Info:
		unreachable()
	}

	return
}

Result_Type :: enum {
	Both,
	Leaks,
	Bad_Frees,
}

tracking_allocator_print_results :: proc(t: ^Tracking_Allocator, type: Result_Type = .Both) {
	context.allocator = t.internals_allocator
	
	Work :: struct {
		trace:   Backtrace,
		result:  []Message,
		err:     Message_Error,
	}

	trace_count: int
	switch type {
	case .Both:
		trace_count = len(t.allocation_map) + len(t.bad_free_array)
	case .Leaks:
		trace_count = len(t.allocation_map)
	case .Bad_Frees:
		trace_count = len(t.bad_free_array)
	}

	work := make([]Work, trace_count)
	defer delete(work)

	i: int
	if type == .Both || type == .Leaks {
		for _, leak in t.allocation_map {
			work[i].trace = leak.backtrace
			i += 1
		}
	}
	
	if type == .Both || type == .Bad_Frees {
		for bad_free in t.bad_free_array {
			work[i].trace   = bad_free.backtrace
			i += 1
		}
	}

	extra_threads := max(0, min(os.processor_core_count() - 1, trace_count - 1))

	extra_threads_done: sync.Wait_Group
	sync.wait_group_add(&extra_threads_done, extra_threads + 1)
	
	// Processes the slice of work given.
	thread_proc :: proc(work: ^[]Work, start: int, end: int, extra_threads_done: ^sync.Wait_Group) {
		defer sync.wait_group_done(extra_threads_done)

		for &entry in work[start:end] {
			entry.result, entry.err = backtrace_messages(entry.trace)
		}
	}

	thread_work := trace_count / extra_threads
	worked: int
	for i in 0..<extra_threads {
		thread.run_with_poly_data4(&work, worked, worked + thread_work, &extra_threads_done, thread_proc)
		worked += thread_work
	}

	thread_proc(&work, worked, len(work), &extra_threads_done)
	sync.wait_group_wait(&extra_threads_done)

	if type == .Both || type == .Leaks {
		work_leaks := work[:len(t.allocation_map)]
		work = work[len(t.allocation_map):]
		li: int
		for _, leak in t.allocation_map {
			defer li+=1

			fmt.eprintf("\x1b[31m%v leaked %v bytes\x1b[0m\n", leak.location, leak.size)
			fmt.eprintln("[back trace]")

			work_leak := work_leaks[li]
			defer messages_delete(work_leak.result)
			if work_leak.err != nil {
				fmt.eprintf("backtrace error: %v\n", work_leak.err)
				continue
			}

			format(work_leak.result)
			fmt.eprintln()
		}

		if len(t.bad_free_array) > 0 do fmt.eprintln()
	}
	
	if type == .Both || type == .Bad_Frees {
		for bad_free, fi in t.bad_free_array {
			fmt.eprintf(
				"\x1b[31m%v allocation %p was freed badly\x1b[0m\n",
				bad_free.location,
				bad_free.memory,
			)
			fmt.eprintln("[back trace]")

			work_free := work[fi]
			defer messages_delete(work_free.result)
			if work_free.err != nil {
				fmt.eprintf("backtrace error: %v\n", work_free.err)
				continue
			}

			format(work_free.result)
			
			if fi + 1 < len(t.bad_free_array) do fmt.eprintln()
		}
	}
}
