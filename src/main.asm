BITS 64
CPU x64

%include "syscalls.mac"

extern x11_init
extern x11_read_response
extern x11_draw_rectangle
extern x11_read_error

section .text
_start:
global _start:function
  call x11_init
  sub rsp, 32

; struct pollfd {
  ; int fd;
  mov DWORD [rsp], r8d
  ; short events;
  mov DWORD [rsp + 4], POLLIN
  ; short revents;
  mov DWORD [rsp + 8], 0
  ; }

  mov BYTE [rsp + 24], 0  ; bool exposed = false

  .loop:
    mov rax, SYSCALL_POLL     
    lea rdi, [rsp]    ; struct pollfd *fds 
    mov rsi, 1        ; nfds_t nfds
    mov rdx, -1       ; int timeout
    syscall

    cmp rax, 0
    jle failure 
    cmp DWORD [rsp + 8], POLLERR
    je failure 
    cmp DWORD [rsp + 8], POLLHUP
    je failure 

    call x11_read_response
    cmp rax, 0xc
    jnz .rec_other_event

    .rec_exposed_event:
      mov BYTE [rsp + 24], 1  ; exposed = true

    .rec_other_event:

    ; if (exposed == true)
    cmp BYTE [rsp + 24], 1    
    jnz .loop

    .draw:
      call x11_draw_rectangle

    jmp .loop

  exit 0

failure:
static failure:function
  exit 1
