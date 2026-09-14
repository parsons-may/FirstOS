[bits 16]
[org 0x7C00]

KERNEL_SEGMENT equ 0x1000
KERNEL_SECTORS equ 15

jmp short start
nop

db "FIRSTBOT"
dw 512
db 1
dw 16
db 2
dw 224
dw 2880
db 0xF0
dw 9
dw 18
dw 2
dd 0
dd 0
db 0
db 0
db 0x29
dd 0x1234ABCD
db "FIRSTOSBOOT"
db "FAT12   "

start:
    cli
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x7C00
    sti

    mov [boot_drive], dl

    mov si, loading_msg
    call print_string

    mov ax, KERNEL_SEGMENT
    mov es, ax
    xor bx, bx
    mov ah, 0x02
    mov al, KERNEL_SECTORS
    mov ch, 0x00
    mov cl, 0x02
    mov dh, 0x00
    mov dl, [boot_drive]
    int 0x13
    jc disk_error

    jmp KERNEL_SEGMENT:0x0000

disk_error:
    mov si, disk_error_msg
    call print_string
    jmp $

print_string:
    lodsb
    test al, al
    jz .done
    mov ah, 0x0E
    mov bh, 0x00
    mov bl, 0x07
    int 0x10
    jmp print_string
.done:
    ret

loading_msg db "Loading tiny OS...", 0
disk_error_msg db 0x0D, 0x0A, "Disk read failed.", 0
boot_drive db 0

times 510 - ($ - $$) db 0
dw 0xAA55
