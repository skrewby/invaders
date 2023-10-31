BITS 64 ; 64 bits.
CPU X64 ; Target the x86_64 family of CPUs.

; ---------------------------- REGISTERS ----------------------------- 
; r8:	Connection socket fd
; r9d:	Window Root ID
; r10d: Graphical Context ID
; r12d: Colormap ID
; r13d: Window ID
; r14d: Font ID
; --------------------------------------------------------------------

%include "syscalls.mac"

%define PROTOCOL_MAJOR_V  11
%define PROTOCOL_MINOR_V  0

section .rodata

sun_path: db "/tmp/.X11-unix/X0", 0
static sun_path:data

window_title: db "Invaders"
static window_title:data

section .data
id: dd 0
static id:data

id_base: dd 0
static id_base:data

id_mask: dd 0
static id_mask:data

root_visual_id: dd 0
static root_visual_id:data

section .text
; Connect to the X11 Server
x11_init:
global x11_init:function
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
  
  call x11_parse_connect_response
  call x11_open_font
  call x11_create_gc
  call x11_create_window
  call x11_map_window
  call x11_set_window_title

  set_socket_non_blocking r8

  add rsp, 112
  pop rbp
  ret 

; Read initial response from server with important data upon initial connection
x11_parse_connect_response:
global x11_parse_connect_response:function
  push rbp
  mov rbp, rsp
  sub rsp, 1<<14

  mov BYTE [rsp], 'l' 
  mov WORD [rsp + 2], PROTOCOL_MAJOR_V 
  mov WORD [rsp + 4], PROTOCOL_MINOR_V 
  mov WORD [rsp + 6], 0                 ; n
  mov WORD [rsp + 8], 0                 ; d

  mov rax, SYSCALL_WRITE
  mov rdi, r8
  lea rsi, [rsp]
  mov rdx, 12
  syscall
  cmp rax, 12
  jne failure

  mov rax, SYSCALL_READ
  mov rdi, r8
  lea rsi, [rsp]
  mov rdx, 1<<15
  syscall

  ; 1 = Success
  cmp BYTE [rsp], 1
  jne failure

  ; resource-id-base
  mov edx, DWORD [rsp + 12]
  mov DWORD [id_base], edx

  ; resource-id-mask
  mov edx, DWORD [rsp + 16]
  mov DWORD [id_mask], edx

  ; length of vendor
  mov dx, WORD [rsp + 24]
  movzx r9, dx            ; v

  ; number for FORMATs in pixmap-formats
  mov dl, BYTE [rsp + 29]
  movzx r13, dl           ; n

  ; Use a pointer to calculate the offset to root-visual for screen 0 in LISTofSCREEN
  lea rsi, [rsp]

  ; Get up to the unused before vendor information
  add rsi, 40
  ; Skip vendor
  add rsi, r9
  ; pad(v) - Round up to nearest 4 multiple
  add rsi, 3
  and rsi, -4
  ; Skip pixmap-formats (size = 8*n)
  mov rcx, r13
  imul rcx, 8
  add rsi, rcx
  ; Window root
  mov r9d, DWORD [rsi]
  ; Skip first 32 bytes of screen information
  add rsi, 32

  ; LISTofSCREEN[0].root-visual
  mov edx, DWORD [rsi]
  mov DWORD [root_visual_id], edx

  add rsp, 1<<14
  pop rbp
  ret

; Increment the global id.
; @return The new id.
x11_next_id:
global x11_next_id:function
  push rbp
  mov rbp, rsp

  mov eax, DWORD [id] ; Load global id.

  mov edi, DWORD [id_base] ; Load global id_base.
  mov edx, DWORD [id_mask] ; Load global id_mask.

  ; Return: id_mask & (id) | id_base
  and eax, edx
  or eax, edi

  add DWORD [id], 1 ; Increment id.

  pop rbp
  ret

; Open the font on the server side.
x11_open_font:
global x11_open_font:function
  push rbp
  mov rbp, rsp
  sub rsp, 20

  ; Get font ID (eax) 
  call x11_next_id 
  mov r14d, eax

  ; Font name: "fixed"
  ; Font size (n): 5
  ; Pad (p): 3
  mov BYTE [rsp], 45        ; Opcode for OpenFont
                            ; Unused - 1 byte
  mov WORD [rsp + 2], 5     ; Request length 3 + (n + p) / 4
  mov DWORD [rsp + 4], r14d ; Font id
  mov WORD [rsp + 8], 5     ; Length of name (n) 
                            ; Unused - 2 bytes
  mov BYTE [rsp + 12], 'f'  ; Name
  mov BYTE [rsp + 13], 'i'  ; |
  mov BYTE [rsp + 14], 'x'  ; |https://www.x.org/releases/X11R7.7/doc/xproto/x11protocol.html#requests:OpenFont
  mov BYTE [rsp + 15], 'e'  ; |
  mov BYTE [rsp + 16], 'd'  ; End Name
                            ; Unused - p - 3 bytes

  mov rax, SYSCALL_WRITE
  mov rdi, r8
  lea rsi, [rsp]
  mov rdx, 20
  syscall

  cmp rax, 20
  jnz failure

  add rsp, 20
  pop rbp
  ret

; Create a X11 Graphical Context
x11_create_gc:
global x11_create_gc:function
  push rbp
  mov rbp, rsp
  sub rsp, 28

  call x11_next_id
  mov r10d, eax		      ; GC ID

  ; Create value mask
  mov ecx, 0
  or ecx, 0x4     ; Foreground
  or ecx, 0x8     ; Background
  or ecx, 0x4000  ; Font

  mov BYTE [rsp], 55          ; CreateGC Opcode
                              ; Unused - 1 Byte
  mov WORD [rsp + 2], 7       ; Request length - 4 + n
  mov DWORD [rsp + 4], r10d   ; cid
  mov DWORD [rsp + 8], r9d    ; Drawable
  mov DWORD [rsp + 12], ecx   ; Value mask
  mov DWORD [rsp + 16], 0xFFFF; Foregroung colour
  mov DWORD [rsp + 20], 0     ; Background colour
  mov DWORD [rsp + 24], r14d  ; Font ID

  mov rax, SYSCALL_WRITE
  mov rdi, r8
  lea rsi, [rsp]
  mov rdx, 28
  syscall
  cmp rax, 28
  jnz failure

  add rsp, 28
  pop rbp
  ret

; Create a X11 window
x11_create_window:
global x11_create_window:function
  push rbp
  mov rbp, rsp
  sub rsp, 40

  call x11_next_id
  mov r13d, eax                   ; Window ID
  mov edx, DWORD [root_visual_id] ; Root Visual ID

  ; Create value mask
  mov ecx, 0
  or ecx, 0x2     ; Background Pixel
  or ecx, 0x800   ; Event mask

  ; Events
  mov ebx, 0
  or ebx, 0x2     ; Key release
  or ebx, 0x8000  ; Exposure

  mov BYTE [rsp], 1         ; CreateWindow Opcode
  mov BYTE [rsp + 1], 0     ; Depth
  mov WORD [rsp + 2], 10    ; Request Length
  mov DWORD [rsp + 4], r13d ; Window ID 
  mov DWORD [rsp + 8], r9d  ; Parent
  mov WORD [rsp + 12], 200  ; Window x
  mov WORD [rsp + 14], 200  ; Window y
  mov WORD [rsp + 16], 800  ; Window width
  mov WORD [rsp + 18], 600  ; Window height
  mov WORD [rsp + 20], 1    ; Border width
  mov WORD [rsp + 22], 1    ; Class - InputOutput
  mov DWORD [rsp + 24], edx ; Root Visual ID
  mov DWORD [rsp + 28], ecx ; Value Mask
  mov DWORD [rsp + 32], 0   ; Background Pixel
  mov DWORD [rsp + 36], ebx ; Events

  mov rax, SYSCALL_WRITE
  mov rdi, r8
  lea rsi, [rsp]
  mov rdx, 40
  syscall
  cmp rax, 40
  jnz failure
  
  add rsp, 40
  pop rbp
  ret

; Map a X11 window.
; @param rdi The socket file descriptor.
; @param esi The window id.
x11_map_window:
global x11_map_window:function
  push rbp
  mov rbp, rsp
  sub rsp, 8

  mov BYTE [rsp], 8         ; MapWindow Opcode
                            ; Unused - 1 byte
  mov WORD [rsp + 2], 2     ; Request Length
  mov DWORD [rsp + 4], r13d ; Window ID
  
  mov rax, SYSCALL_WRITE
  mov rdi, r8
  lea rsi, [rsp]
  mov rdx, 8
  syscall
  cmp rax, 8
  jnz failure

  add rsp, 8
  pop rbp
  ret

x11_set_window_title:
static x11_set_window_title:function
  push rbp
  mov rbp, rsp
  sub rsp, 32

  mov BYTE [rsp], 18        ; ChangeProperty Opcode
  mov BYTE [rsp + 1], 0     ; Replace
  mov WORD [rsp + 2], 8     ; Request length 6+(n+p)/4
  mov DWORD [rsp + 4], r13d ; Window ID
  mov DWORD [rsp + 8], 39   ; Property: WM_NAME
  mov DWORD [rsp + 12], 31  ; Type: String
  mov BYTE [rsp + 16], 8    ; Format: List of 8 bits
                            ; Unused - 3 Bytes
  mov DWORD [rsp + 20], 8   ; Length in format units (8 * 8bits in this case)
  
  ; Copy window title string to stack
  lea rsi, window_title
  lea rdi, [rsp + 24]
  cld
  mov rcx, 8 
  rep movsb

  mov rax, SYSCALL_WRITE
  mov rdi, r8
  lea rsi, [rsp]
  mov rdx, 32
  syscall

  add rsp, 32
  pop rbp
  ret

failure:
static failure:function
  exit 1

; Read X11 Server response
; @return rax First byte of response
x11_read_response:
global x11_read_response:function
  push rbp
  mov rbp, rsp
  sub rsp, 32

  mov rax, SYSCALL_READ
  mov rdi, r8
  lea rsi, [rsp]
  mov rdx, 32
  syscall

  movzx rax, BYTE [rsp]

  add rsp, 32
  pop rbp
  ret

x11_read_error:
global x11_read_error:function
  push rbp
  mov rbp, rsp
  sub rsp, 32

  mov rax, SYSCALL_READ
  mov rdi, r8
  lea rsi, [rsp]
  mov rdx, 32
  syscall

  mov rax, SYSCALL_WRITE
  mov rdi, STDOUT
  lea rsi, [rsp]
  mov rdx, 32
  syscall

  add rsp, 32
  pop rbp
  ret

x11_create_colormap:
static x11_create_colormap:function
  push rbp
  mov rbp, rsp
  sub rsp, 16

  ; Get Colormap ID (eax) 
  call x11_next_id 
  mov r12d, eax

  mov edx, DWORD [root_visual_id] ; Root Visual ID

  mov BYTE [rsp], 78        ; CreateColormap Opcode
  mov BYTE [rsp + 1], 0     ; Alloc - None 
  mov WORD [rsp + 2], 4     ; Request length
  mov DWORD [rsp + 4], r12d ; Colormap ID
  mov DWORD [rsp + 8], r13d ; Window ID
  mov DWORD [rsp + 12], edx ; Visual ID

  mov rax, SYSCALL_WRITE
  mov rdi, r8
  lea rsi, [rsp]
  mov rdx, 16 
  syscall
  cmp rax, 16
  jne failure

  add rsp, 16
  pop rbp
  ret

x11_draw_rectangle:
global x11_draw_rectangle:function
  push rbp
  mov rbp, rsp
  sub rsp, 20

  mov BYTE [rsp], 70        ; PolyFillRectangle Opcode
                            ; Unused - 1 byte
  mov WORD [rsp + 2], 5     ; Request length: 3 + 2n
  mov DWORD [rsp + 4], r13d ; Drawable 
  mov DWORD [rsp + 8], r10d ; GC
  mov WORD [rsp + 12], 300  ; Rectangle x
  mov WORD [rsp + 14], 200  ; Rectangle y
  mov WORD [rsp + 16], 200  ; Rectangle width
  mov WORD [rsp + 18], 200  ; Rectangle height

  mov rax, SYSCALL_WRITE
  mov rdi, r8
  lea rsi, [rsp]
  mov rdx, 20
  syscall
  cmp rax, 20
  jne failure

  add rsp, 20
  pop rbp
  ret
