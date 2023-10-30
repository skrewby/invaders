BITS 64
CPU x64

%include "syscalls.mac"

extern x11_init
extern x11_poll_events

section .text
_start:
global _start:function
  call x11_init
  call x11_poll_events

  exit 0
