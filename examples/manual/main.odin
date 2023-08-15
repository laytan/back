package manual

import "core:fmt"

import bt "../.."

main :: proc() {
	trace := bt.backtrace_get(16)
	defer bt.backtrace_delete(trace)

	messages, err := bt.backtrace_messages(trace)
	fmt.assertf(err == nil, "err: %v", err)
	defer bt.messages_delete(messages)

	fmt.println("[back trace]")
	for message in messages {
		fmt.printf("    %s - %s\n", message.symbol, message.location)
	}
}
