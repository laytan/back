package main

import back "../.."

main :: proc() {
	context.assertion_failure_proc = back.assertion_failure_proc
	assert(3 == 2)
}
