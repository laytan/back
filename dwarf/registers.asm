bits 64

section .text

global registers_current
registers_current:
	mov r9, [rsp]
	mov QWORD [rdi], r9
	mov QWORD [rdi + 8], 1

	mov [rdi + 16], rsp
	add QWORD [rdi + 16], 8
	mov QWORD [rdi + 24], 1

	mov [rdi + 32], rbp
	mov QWORD [rdi + 40], 1

	ret
