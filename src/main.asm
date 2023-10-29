BITS 64
CPU x64

%include "syscalls.mac"

extern x11_connect
extern x11_init

section .text
_start:
global _start:function
  call x11_connect
  call x11_init

  exit 0
