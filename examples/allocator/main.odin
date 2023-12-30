package main

import back "../.."

_main :: proc() {
	_ = new(int)
	free(rawptr(uintptr(100)))
}

main :: proc() {
	track: back.Tracking_Allocator
	back.tracking_allocator_init(&track, context.allocator)
	defer back.tracking_allocator_destroy(&track)

	context.allocator = back.tracking_allocator(&track)
	defer back.tracking_allocator_print_results(&track)

	_main()
}
