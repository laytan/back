package manual

import "core:fmt"

import bt "../.."

main :: proc() {
	backtrace, size := bt.backtrace_get(16)
	defer bt.backtrace_delete(backtrace)
	messages := bt.backtrace_messages(backtrace, size)
	defer delete(messages)

	fmt.println("[back trace]")
	for message in messages {
		defer delete(message)
		fmt.printf("    %s\n", message)
	}
}
