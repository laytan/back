package obacktracing

import "core:fmt"
import "core:mem"
import "core:runtime"
import "core:sync"

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
	backtrace_max_length: i32,
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
	backtrace_max_length: i32,
	backing_allocator: mem.Allocator,
	internals_allocator := context.allocator,
) {
	t.backing = backing_allocator
	t.internals_allocator = internals_allocator
	t.allocation_map.allocator = internals_allocator
	t.bad_free_array.allocator = internals_allocator

	// 2 entries are internal (for retrieving the backtrace), we exclude those.
	t.backtrace_max_length = backtrace_max_length + 2

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
				backtrace = backtrace_get(data.backtrace_max_length, data.internals_allocator),
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
			backtrace = backtrace_get(data.backtrace_max_length, data.internals_allocator),
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
			backtrace = backtrace_get(data.backtrace_max_length, data.internals_allocator),
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

tracking_allocator_print_results :: proc(t: ^Tracking_Allocator) {
	context.allocator = t.internals_allocator

	for _, leak in t.allocation_map {
		fmt.printf("\x1b[31m%v leaked %v bytes\x1b[0m\n", leak.location, leak.size)
		fmt.println("[back trace]")
		msgs, err := backtrace_messages(leak.backtrace)
		fmt.assertf(err == nil, "backtrace error: %v", err)
		defer messages_delete(msgs)
		format(msgs)
		fmt.println()
	}

	if len(t.bad_free_array) > 0 do fmt.println()

	for bad_free, i in t.bad_free_array {
		fmt.printf(
			"\x1b[31m%v allocation %p was freed badly\x1b[0m\n",
			bad_free.location,
			bad_free.memory,
		)
		fmt.println("[back trace]")
		msgs, err := backtrace_messages(bad_free.backtrace)
		fmt.assertf(err == nil, "backtrace error: %v", err)
		defer messages_delete(msgs)
		format(msgs)
		if i + 1 < len(t.bad_free_array) do fmt.println()
	}
}
