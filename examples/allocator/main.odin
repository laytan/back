package main

import bt "../.."

_main :: proc() {
	_ = new(int)
	free(rawptr(uintptr(100)))
}

main :: proc() {
	track: bt.Tracking_Allocator
	bt.tracking_allocator_init(&track, 16, context.allocator)
	bt.tracking_allocator_destroy(&track)
	defer bt.tracking_allocator_destroy(&track)
	context.allocator = bt.tracking_allocator(&track)

	_main()

	bt.tracking_allocator_print_results(&track)
}
