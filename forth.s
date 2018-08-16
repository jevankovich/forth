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

        mov     rsi, rax
        add     rsi, 8          ; point rsi at the first sub-word
        jmp     next

doconst:
        push    rbx             ; push down the top-of-stack
        mov     rbx, [rax + 8]
        jmp     next

dovar:
        push    rbx             ; push down the top-of-stack
        mov     rbx, rax
        add     rbx, 8
        jmp     next

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

primitive done  ; terminates the colon defined word
        mov     rsi, [rbp]      ; pop the instruction pointer from the return stack
        add     rbp, 8
        jmp     next

primitive imm   ; ( -- x )
        push    rbx
        mov     rbx, [rsi]
        add     rsi, 8
        jmp     next

primitive add,'+'       ; ( a b -- a+b )
        pop     rax
        add     rbx, rax
        jmp     next

primitive or            ; ( a b -- a|b )
        pop     rax
        or      rbx, rax
        jmp     next

primitive eq,'='        ; ( a b -- bool )
        pop     rax
        cmp     rax, rbx
        je      .eq
        mov     rbx, 0
        jmp     next
.eq:    mov     rbx, -1
        jmp     next

primitive branch,'branch' ; ( -- ) increments the program counter by imm
                          ; branch 0 is a nop
        mov     rax, [rsi]
        imul    rax, 8
        add     rsi, rax        ; skip imm instructions
        add     rsi, 8          ; skip one more because of the imm
        jmp     next

primitive cbranch,'?branch' ; ( bool -- ) increments the program counter by imm if top of stack is false
                            ; ?branch 0 is a nop
        pop     rax
        test    rbx, rbx
        jnz     .done
        mov     rbx, [rsi]
        imul    rbx, 8
        add     rsi, rbx        ; skip imm instructions

.done:  add     rsi, 8          ; skip a single instruction (e.g. skip the immediate)
        mov     rbx, rax
        jmp     next

primitive sub,'-'       ; ( a b -- a-b )
        pop     rax
        sub     rax, rbx
        mov     rbx, rax
        jmp     next

primitive dup   ; ( a -- a a )
        push    rbx
        jmp     next

primitive swap  ; ( a b -- b a )
        pop     rax
        push    rbx
        mov     rbx, rax
        jmp     next

primitive drop ; ( a -- )
        pop     rbx
        jmp     next

primitive roll ; ( a b c -- b c a )
        pop     rax
        pop     rcx
        push    rax
        push    rbx
        mov     rbx, rcx
        jmp     next

primitive load,'@'      ; ( a -- [a] )
        mov     rbx, [rbx]
        jmp     next

primitive loadb,'@b'    ; ( a -- [a] )
        xor     rax, rax
        mov     al, [rbx]       ; read the byte at rbx
        mov     rbx, rax
        jmp     next

primitive store,'!'     ; ( x a -- ) stores x at a
        pop     rax
        mov     [rbx], rax
        pop     rbx
        jmp     next

primitive storeb,'!b'   ; ( b a -- ) stores b at a
        pop     rax
        mov     [rbx], al
        pop     rbx
        jmp     next

primitive exit  ; ( x -- )
        mov     rax, 60         ; exit
        mov     rdi, rbx        ; exit code rbx
        syscall

primitive read  ; ( fd buf count -- bytes-read )
        mov     r8, rsi         ; save rsi
        mov     rax, 0          ; read
        mov     rdx, rbx        ; count is top of stack
        pop     rsi             ; buf is next
        pop     rdi             ; then fd
        syscall
        mov     rbx, rax        ; put return value on top of stack
        mov     rsi, r8         ; restore rsi
        jmp     next

primitive write ; ( fd buf count -- bytes-read )
        mov     r8, rsi         ; save rsi
        mov     rax, 1          ; write
        mov     rdx, rbx        ; count is top of stack
        pop     rsi             ; buf is next
        pop     rdi             ; then fd
        syscall
        mov     rbx, rax        ; put return value on top of stack
        mov     rsi, r8         ; restore rsi
        jmp     next

colon incvar    ; ( v -- )
; dup @ 1 + swap !
        dq      x_dup
        dq      x_load
        dq      x_imm,1
        dq      x_add
        dq      x_swap
        dq      x_store
        dq      x_done

colon getc      ; ( -- c )
; buf_in_len @ buf_in_ind @ = if
;       stdin buf_in buf_in_size read buf_in_len ! 
;       0 buf_in_ind !
;       then
; buf_in buf_in_ind @ + @b
; buf_in_ind incvar
        dq      x_buf_in_len
        dq      x_load
        dq      x_buf_in_ind
        dq      x_load
        dq      x_eq
        dq      x_cbranch,9

        dq      x_stdin
        dq      x_buf_in
        dq      x_buf_in_size
        dq      x_read
        dq      x_buf_in_len
        dq      x_store

        dq      x_zero
        dq      x_buf_in_ind
        dq      x_store

        dq      x_buf_in
        dq      x_buf_in_ind
        dq      x_load
        dq      x_add
        dq      x_loadb

        dq      x_buf_in_ind
        dq      x_incvar
        
        dq      x_done

colon putc      ; ( c -- )
; dup
; buf_out buf_out_len @ + !b
; buf_out_len incvar 
; '\n' = buf_out_size buf_out_len @ = or if
;       stdout buf_out buf_out_len @ write drop
;       0 buf_out_len !
;       then
        dq      x_dup

        dq      x_buf_out
        dq      x_buf_out_len
        dq      x_load
        dq      x_add
        dq      x_storeb

        dq      x_buf_out_len
        dq      x_incvar

        dq      x_imm,10        ; \n
        dq      x_eq
        dq      x_buf_out_size
        dq      x_buf_out_len
        dq      x_load
        dq      x_eq
        dq      x_or
        dq      x_cbranch,9

        dq      x_stdout
        dq      x_buf_out
        dq      x_buf_out_len
        dq      x_load
        dq      x_write
        dq      x_drop

        dq      x_zero
        dq      x_buf_out_len
        dq      x_store

        dq      x_done

colon main
; getc putc branch -4
        dq      x_getc,x_putc
        dq      x_branch,-4

section .data

constant zero,'0'       ; convenience constant
        dq      0

constant stdin
        dq      0

constant stdout
        dq      1

%define buf_size 512

constant buf_in
        dq      buf_in

constant buf_in_size
        dq      buf_size

variable buf_in_len
        dq      0

variable buf_in_ind
        dq      0

constant buf_out
        dq      buf_out

constant buf_out_size
        dq      buf_size

variable buf_out_len
        dq      0

variable dict
        dq      link

section .bss
        resq    1024
r_stack:

buf_in: resb    buf_size
buf_out:resb    buf_size
