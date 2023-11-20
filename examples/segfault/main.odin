package main

import bt "../.."

main :: proc() {
	bt.register_segfault_handler()

	ptr: ^int
	bad := ptr^ + 2
}
