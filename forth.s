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

doconst:
        push    rbx             ; push down the top-of-stack
        mov     rbx, [rax + 8]
        jmp     next

dovar:
        push    rbx             ; push down the top-of-stack
        mov     rbx, rax
        add     rbx, 8
        jmp     next

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

%define link    0

%macro head 1
%defstr %%name  %1
head    %1, %%name
%endmacro

%macro head 2
        align   8
%%link: dq      link
%define link    %%link

%strlen %%namelen %2
        db      %%namelen, %2
x_ %+ %1:
%endmacro

%macro  primitive 1+
head    %1
        dq      $+8
%endmacro

%macro  colon 1+
head    %1
        dq      docolon
%endmacro

%macro  constant 1+
head    %1
        dq      doconst
%endmacro

%macro  variable 1+
head    %1
        dq      dovar
%endmacro

primitive done
        mov     rsi, [rbp]      ; pop the instruction pointer from the return stack
        add     rbp, 8
        jmp     next

primitive imm
        push    rbx
        mov     rbx, [rsi]
        add     rsi, 8
        jmp     next

primitive add,'+'
        pop     rax
        add     rbx, rax
        jmp     next

primitive sub,'-'
        pop     rax
        sub     rax, rbx
        mov     rbx, rax
        jmp     next

primitive dup
        push    rbx
        jmp     next

primitive swap
        pop     rax
        push    rbx
        mov     rbx, rax
        jmp     next

primitive drop
        pop     rbx
        jmp     next

primitive roll
        pop     rax
        pop     rcx
        push    rax
        push    rbx
        mov     rbx, rcx
        jmp     next

primitive load,'@'
        mov     rbx, [rbx]
        jmp     next

primitive store,'!'
        pop     rax
        mov     [rax], rbx
        pop     rbx
        jmp     next

primitive exit
        mov     rax, 60         ; exit
        mov     rdi, rbx        ; exit code rbx
        syscall

colon main
        dq      x_imm,3
        dq      x_imm,-3
        dq      x_add
        dq      x_exit

section .data

constant buf_in
        dq      buf_in

variable buf_in_len
        dq      0

variable buf_in_ind
        dq      0

constant buf_out
        dq      buf_out

variable buf_out_len
        dq      0

variable dict
        dq      link

section .bss
        resq    1024
r_stack:

buf_in: resb    4096
buf_out:resb    4096
