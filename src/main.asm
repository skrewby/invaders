BITS 64
CPU x64

%include "syscalls.mac"

extern x11_connect

section .text
_start:
global _start:function
  call x11_connect

  exit 0
