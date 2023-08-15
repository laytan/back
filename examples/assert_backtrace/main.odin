package main

import bt "../.."

main :: proc() {
    context.assertion_failure_proc = bt.assertion_failure_proc
    assert(3 == 2)
}
