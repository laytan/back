package main

import back "../.."

main :: proc() {
	back.register_segfault_handler()

	ptr: ^int
	bad := ptr^ + 2
	_ = bad
}
