forth: forth.o
	ld -g -o forth forth.o

forth.o: forth.s
	nasm -felf64 -Fdwarf -g forth.s
