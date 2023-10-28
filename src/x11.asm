BITS 64
CPU x64

%include "syscalls.mac"

section .rodata
sun_path: db "/tmp/.X11-unix/X0", 0
static sun_path:data

section .text
x11_connect:
global x11_connect:function
  push rbp
  mov rbp, rsp
  sub rsp, 112    ; sockaddr_un = 110, align to 16 with 112 

  open_socket
  cmp rax, 0
  jle failure

  mov r8, rax     ; Socket fd
  
  ; struct sockaddr_un {
  ;   sa_family_t sun_family;
  mov WORD [rsp], AF_UNIX
  ;   char        sun_path[108];
  lea rsi, sun_path
  lea rdi, [rsp + 2]
  cld
  mov rcx, 19
  rep movsb
  ; }

  connect_socket r8,[rsp]
  cmp rax, 0
  jne failure
   
  add rsp, 112
  pop rbp
  ret

failure:
static failure:function
  exit 1
