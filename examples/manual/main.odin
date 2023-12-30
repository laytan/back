package manual

import "core:fmt"

import bt "../.."

main :: proc() {
	trace := bt.backtrace_get(16)
	defer bt.backtrace_delete(trace)

	messages, err := bt.backtrace_messages(trace)
	if err != nil {
		fmt.eprintf("Could not retrieve backtrace: %v\n", err)
	} else {
		defer bt.messages_delete(messages)

		fmt.println("[back trace]")
		bt.format(messages)
	}
}
