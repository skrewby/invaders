#!/bin/bash

mkdir -p build
mkdir -p bin

nasm -f elf64 -g -i src/ src/main.asm -o build/main.o
nasm -f elf64 -g -i src/ src/x11.asm -o build/x11.o
ld build/main.o build/x11.o -static -o bin/invaders
