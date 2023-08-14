package obacktracing

import "core:c"
import "core:c/libc"
import "core:fmt"
import "core:os"
import "core:strings"
import "core:sync"
import "core:thread"
import "core:mem"
import "core:runtime"

// NOTE: not sure if this works on anything other than linux.
when ODIN_OS == .Windows {
	foreign import libc_ "system:libucrt.lib"
} else when ODIN_OS == .Darwin {
	foreign import libc_ "system:System.framework"
} else {
	foreign import libc_ "system:c"
}

foreign libc_ {
	backtrace :: proc(buffer: [^]rawptr, size: c.int) -> c.int ---
	backtrace_symbols :: proc(buffer: [^]rawptr, size: c.int) -> [^]cstring ---
	backtrace_symbols_fd :: proc(buffer: [^]rawptr, size: c.int, fd: ^libc.FILE) ---

    @private
	popen :: proc(command: cstring, type: cstring) -> ^libc.FILE ---
    @private
	pclose :: proc(stream: ^libc.FILE) -> c.int ---
}

backtrace_get :: proc($N: c.int) -> (backt: [^]cstring, size: c.int) {
	trace: [N]rawptr
	trace_ptr := raw_data(trace[:])
	size = backtrace(trace_ptr, N)
	backt = backtrace_symbols(trace_ptr, size)
	return
}

backtrace_delete :: proc(backtrace: [^]cstring) {
	libc.free(backtrace)
}

Message_Error :: enum {
    Not_Debug,
    Parse_Address_Fail,
    Addr2line_No_Output,
    Addr2line_Output_Error,
    Addr2line_Unresolved,
    Fork_Limited         = int(os.EAGAIN),
    Out_Of_Memory        = int(os.ENOMEM),
    Invalid_Fd           = int(os.EFAULT),
    Pipe_Process_Limited = int(os.EMFILE),
    Pipe_System_Limited  = int(os.ENFILE),
    Fork_Not_Supported   = int(os.ENOSYS),
}

// Processes all lines of the backtrace using backtrace_message() multithreaded.
// TODO: errors
// TODO: accept allocator
backtrace_messages :: proc(backtrace: [^]cstring, size: c.int) -> []string {
    size := int(size)
    out := make([]string, size)
    when !ODIN_DEBUG {
        for message, i in backtrace[:size] {
            out[i] = strings.clone_from(message)
        }
    } else {
        wg: sync.Wait_Group
        num_threads := min(size, os.processor_core_count())
        sync.wait_group_add(&wg, size)
        for message, i in backtrace[:size] {
            thread.create_and_start_with_poly_data4(
                &wg,
                message,
                &out,
                i,
                proc(wg: ^sync.Wait_Group, message: cstring, out: ^[]string, i: int) {
                    defer sync.wait_group_done(wg)
                    msg, err := backtrace_message(message)
                    assert(err == nil || err == .Addr2line_Unresolved)
                    out^[i] = msg
                },
                context,
                self_cleanup = true,
            )
        }

        sync.wait_group_wait(&wg)
    }

    return out
}

// Processes the message trying to get more/useful information.
// This adds file and line information if the program is running in debug mode.
//
// The `program` arg should be the file path of the executable.
// You can leave this nil and it will default to os.args[0].
//
// If an error is returned the original message will be the result and is save to use.
backtrace_message :: proc(
    msg: cstring,
    program: Maybe(string) = nil,
    allocator := context.allocator,
) -> (string, Message_Error) {
	when !ODIN_DEBUG {
        return strings.clone_from(msg, allocator), nil
    } else {
        // Parses the address out of a backtrace line.
        // Example: .../main() [0x100000] -> 0x100000
        parse_address :: proc(msg: cstring) -> (string, bool) {
            multi := transmute([^]byte)msg
            msg_len := len(msg)
            start := -1
            #reverse for c, i in multi[:msg_len] {
                if c == '[' {
                    return string(multi[i+1:msg_len-1]), true
                }
            }
            return "", false
        }

        addr, ok := parse_address(msg)
        if !ok do return strings.clone_from(msg, allocator), .Parse_Address_Fail

        p := program.? or_else os.args[0]
        command := fmt.caprintf("addr2line %s -e %s", addr, p)
        defer delete(command)

        fp := popen(command, "r")
        if fp == nil do return strings.clone_from(msg, allocator), Message_Error(libc.errno()^)
        defer pclose(fp)

        out, merr := make([]byte, 4096)
        if merr != nil do return strings.clone_from(msg, allocator), .Out_Of_Memory
        defer delete(out)

        got := libc.fgets(raw_data(out), c.int(len(out)), fp)
        if got == nil {
            ret := strings.clone_from(msg, allocator)
            ferr := Message_Error.Addr2line_Output_Error
            if libc.feof(fp) == 0 do ferr = .Addr2line_No_Output
            return ret, ferr
        }

        // Some lines just can't be found, not necessarily an error.
        if out[0] == '?' && out[1] == '?' {
            return strings.clone_from(msg, allocator), .Addr2line_Unresolved
        }

        cout := cstring(raw_data(out))
        ret := strings.clone_from(cout, allocator)
        ret = strings.trim_right_space(ret)
        return ret, nil
    }

    unreachable()
}

// The backtrace tracking allocator is the same allocator as the core tracking allocator but keeps
// backtraces for each allocation.
// See examples/allocator for a usage snippet.
Backtrace_Tracking_Allocator :: struct {
	backing:           mem.Allocator,
	allocation_map:    map[rawptr]Backtrace_Tracking_Allocator_Entry,
	bad_free_array:    [dynamic]Backtrace_Tracking_Allocator_Bad_Free_Entry,
	mutex:             sync.Mutex,
	clear_on_free_all: bool,
}

Backtrace_Tracking_Allocator_Entry :: struct {
	memory:         rawptr,
	size:           int,
	alignment:      int,
	mode:           mem.Allocator_Mode,
	err:            mem.Allocator_Error,
	backtrace:      [^]cstring,
	backtrace_size: c.int,
	location:       runtime.Source_Code_Location,
}

Backtrace_Tracking_Allocator_Bad_Free_Entry :: struct {
	memory:   rawptr,
	location: runtime.Source_Code_Location,
	backtrace:      [^]cstring,
	backtrace_size: c.int,
}

backtrace_tracking_allocator_init :: proc(
	t: ^Backtrace_Tracking_Allocator,
	backing_allocator: mem.Allocator,
	internals_allocator := context.allocator,
) {
	t.backing = backing_allocator
	t.allocation_map.allocator = internals_allocator
	t.bad_free_array.allocator = internals_allocator

	if .Free_All in mem.query_features(t.backing) {
		t.clear_on_free_all = true
	}
}

backtrace_tracking_allocator_destroy :: proc(t: ^Backtrace_Tracking_Allocator) {
    for _, leak in t.allocation_map do backtrace_delete(leak.backtrace)
	delete(t.allocation_map)

    for bad_free in t.bad_free_array do backtrace_delete(bad_free.backtrace)
	delete(t.bad_free_array)
}


backtrace_tracking_allocator_clear :: proc(t: ^Backtrace_Tracking_Allocator) {
    sync.guard(&t.mutex)

    for _, leak in t.allocation_map do backtrace_delete(leak.backtrace)
    clear(&t.allocation_map)

    for bad_free in t.bad_free_array do backtrace_delete(bad_free.backtrace)
    clear(&t.bad_free_array)
}

@(require_results)
backtrace_tracking_allocator :: proc(data: ^Backtrace_Tracking_Allocator) -> mem.Allocator {
	return mem.Allocator{data = data, procedure = backtrace_tracking_allocator_proc}
}

backtrace_tracking_allocator_proc :: proc(
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
	data := (^Backtrace_Tracking_Allocator)(allocator_data)

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
        bt, bt_size := backtrace_get(16)
		append(
			&data.bad_free_array,
			Backtrace_Tracking_Allocator_Bad_Free_Entry{
                memory = old_memory,
                location = loc,
                backtrace = bt,
                backtrace_size = bt_size,
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
        bt, bt_size := backtrace_get(16)
		data.allocation_map[result_ptr] = Backtrace_Tracking_Allocator_Entry {
			memory         = result_ptr,
			size           = size,
			mode           = mode,
			alignment      = alignment,
			err            = err,
			location       = loc,
			backtrace      = bt,
            backtrace_size = bt_size,
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
        // TODO: allow changing depth.
        bt, bt_size := backtrace_get(16)
		data.allocation_map[result_ptr] = Backtrace_Tracking_Allocator_Entry {
			memory         = result_ptr,
			size           = size,
			mode           = mode,
			alignment      = alignment,
			err            = err,
			location       = loc,
			backtrace      = bt,
            backtrace_size = bt_size,
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
