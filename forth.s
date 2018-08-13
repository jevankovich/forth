; rax           currently executing instruction
; rbx           top of stack
; rcx           temporary
; rdx           temporary
; rsi           forth instruction pointer
; rdi
; rsp           pointer to top of data stack
; rbp           pointer to top of return stack
; r8-r15        temporary

        bits 64
        global _start

section .text
_start: mov     rbp, r_stack    ; rbp is top of return stack
        mov     rsi, x_main + 8 ; Start inside of main
        ;jmp    next            ; No need to actually execute this, just fall-through

; next is jumped to at the end of a primitive word
; It loads the next forth instruction and jumps to it
next:
        lodsq                   ; Loads the forth instruction at rsi into rax
        jmp     [rax]           ; Jump to the execution target of the instruction

; docolon pushes to the return stack and executes the word pointed to by rax
; rax is a pointer to the docolon reference that was invoked
; therefore, [rax] is just docolon
;            [rax + 8] is the first sub-word
docolon:
        sub     rbp, 8
        mov     [rbp], rsi      ; push the current instruction pointer

        add     rax, 8
        mov     rsi, [rax]
        jmp     [rsi]

;doconst:
;        push    rbx             ; push down the top-of-stack
;        mov     rbx, [rax + 8]
;        jmp     next
;
;dovar:
;        push    rbx             ; push down the top-of-stack
;        mov     rbx, rax
;        add     rbx, 8
;        jmp     next

;; Reads a single byte from standard in.
;; The read byte is returned as a 16 bit number in ax.
;; If the returned number is negative, EOF has been reached
;getc:   mov     r8, [buf_in_ind]; r8 is the current index into the buffer
;        cmp     r8, [buf_in_len]
;        jne     getc_skip_read
;          mov   rdi, 0          ; stdin
;          mov   rsi, buf_in
;          mov   rdx, 4096
;          mov   rax, 0          ; read
;          syscall
;
;          cmp   rax, 0
;          jg    getc_eof
;            mov ax, -1
;            ret
;getc_eof:
;          mov   [buf_in_len], rax
;          mov   r8, 0           ; reset the index
;          mov qword [buf_in_ind], 0
;getc_skip_read:
;        xor     ax, ax
;        mov     al, [buf_in + r8]
;        inc     r8
;        mov     [buf_in_ind], r8; store the index
;        ret
;
;; Writes the character in dil to standard out.
;putc:   mov     r8, [buf_out_len]
;        mov     [buf_out + r8], dil
;        inc     r8
;        mov     [buf_out_len], r8
;        ; If newline or we reach the end of the buffer, flush the buffer
;        cmp     dil, 10
;        je      putc_write
;        cmp     r8, 4096
;        jl      putc_write
;        
;        ret
;putc_write:
;        mov     rax, 1          ; write()
;        mov     rdi, 1          ; stdout
;        mov     rsi, buf_out
;        mov     rdx, r8         ; [buf_out_len] is the number of bytes in the buffer
;        syscall
;        mov word [buf_out_len], 0
;        ret

; The format of a dictionary entry is as follows
;       align 8
; e_<tag>: (The (E)ntry label)
;       dq      <pointer to next entry>
;       db      <length of name>
;       db      <name>
;       align   8
; x_<tag>: (The e(X)ecution label)
;       dq      <jump target to execute, e.g. docolon>
;       <dependent on the executer>

; done
        align   8
e_done: dq      0
        db      4,'done'
x_done: dq      $+8
        mov     rsi, [rbp]      ; pop the instruction pointer from the return stack
        add     rbp, 8
        jmp     next

; immediate
        align   8
e_imm:  dq      e_done
        db      3,'imm'
x_imm:  dq      $+8
        push    rbx
        mov     rbx, [rsi]
        add     rsi, 8
        jmp     next

; add
        align   8
e_add   dq      e_imm
        db      1,'+'
x_add:  dq      $+8
        pop     rax
        add     rbx, rax
        jmp     next

; exit
        align   8
e_exit: dq      e_add
        db      4,'exit'
x_exit: dq      $+8
        mov     rax, 60         ; exit
        mov     rdi, rbx        ; exit code rbx
        syscall

; main
        align   8
e_main: dq      e_exit
        db      4,'main'
x_main: dq      docolon
        dq      x_imm,3
        dq      x_imm,-3
        dq      x_add
        dq      x_exit

section .bss
        resq    1024
r_stack:

buf_in_len:
        resq    1
buf_in_ind:
        resq    1
buf_in: resb    4096

buf_out_len:
        resq    1
buf_out:resb    4096
