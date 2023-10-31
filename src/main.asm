BITS 64
CPU x64

%include "syscalls.mac"

extern x11_init
extern x11_read_response

section .text
_start:
global _start:function
  call x11_init

; struct pollfd {
  ; int fd;
  mov DWORD [rsp], r8d
  ; short events;
  mov DWORD [rsp + 4], POLLIN
  ; short revents;
  mov DWORD [rsp + 8], 0
  ; }

  .loop:
    mov rax, SYSCALL_POLL     
    lea rdi, [rsp]    ; struct pollfd *fds 
    mov rsi, 1        ; nfds_t nfds
    mov rdx, -1       ; int timeout
    syscall

    call x11_read_response

    cmp rax, 0
    jle failure 
    cmp DWORD [rsp + 8], POLLERR
    je failure 
    cmp DWORD [rsp + 8], POLLHUP
    je failure 

    jmp .loop

  exit 0

failure:
static failure:function
  exit 1
