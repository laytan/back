#+vet explicit-allocators
#+build !linux
#+build !darwin
#+build !netbsd
#+build !openbsd
#+build !freebsd
#+build !windows
package back

@(private="package")
_register_segfault_handler :: proc() {}
