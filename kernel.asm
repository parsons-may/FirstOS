[bits 16]
[org 0x0000]

KERNEL_SEGMENT      equ 0x1000
SECTOR_SIZE         equ 512
ROOT_DIR_LBA        equ 34
ROOT_DIR_SECTORS    equ 14
FAT1_LBA            equ 16
SECTORS_PER_FAT     equ 9
DATA_START_LBA      equ 48
SECTORS_PER_TRACK   equ 18
HEADS               equ 2
INPUT_MAX           equ 64

start:
    cli
    mov ax, KERNEL_SEGMENT
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0xFFFE
    mov [boot_drive], dl
    sti

    call clear_screen
    mov si, banner
    call print_string

shell_loop:
    mov si, prompt
    call print_string
    call read_line

    mov si, input_buffer
    call uppercase_string

    cmp byte [input_buffer], 0
    je shell_loop

    mov si, input_buffer
    mov di, cmd_help
    call strings_equal
    jc .do_help

    mov si, input_buffer
    mov di, cmd_cls
    call strings_equal
    jc .do_cls

    mov si, input_buffer
    mov di, cmd_ver
    call strings_equal
    jc .do_ver

    mov si, input_buffer
    mov di, cmd_reboot
    call strings_equal
    jc .do_reboot

    mov si, input_buffer
    mov di, cmd_list
    call strings_equal
    jc .do_list

    mov si, input_buffer
    mov di, cmd_about
    call strings_equal
    jc .do_about

    mov si, input_buffer
    mov di, cmd_echo
    call starts_with
    jc .do_echo

    mov si, input_buffer
    mov di, cmd_type
    call starts_with
    jc .do_type

    mov si, input_buffer
    mov di, cmd_rename
    call starts_with
    jc .do_rename

    mov si, input_buffer
    mov di, cmd_delete
    call starts_with
    jc .do_delete

    jmp unknown_command

.do_help:
    mov si, help_msg
    call print_string
    jmp shell_loop

.do_cls:
    call clear_screen
    jmp shell_loop

.do_ver:
    mov si, version_msg
    call print_string
    jmp shell_loop

.do_reboot:
    mov si, reboot_msg
    call print_string
    xor ax, ax
    int 0x16
    int 0x19
    jmp $

.do_list:
    call list_files
    jmp shell_loop

.do_about:
    mov si, about_msg
    call print_string
    jmp shell_loop

.do_echo:
    mov si, input_buffer + 4
    call skip_spaces
    cmp byte [si], 0
    je echo_usage
    call print_string
    call print_newline
    call print_newline
    jmp shell_loop

.do_type:
    mov si, input_buffer + 4
    call skip_spaces
    cmp byte [si], 0
    je type_usage

    mov di, fat_name_buffer
    call format_fat_filename
    jnc bad_filename

    call find_file
    jnc file_not_found

    call type_file
    jmp shell_loop

.do_rename:
    mov si, input_buffer + 6
    call skip_spaces
    cmp byte [si], 0
    je rename_usage

    mov di, fat_name_buffer
    call format_fat_filename
    jnc bad_filename

    call skip_token
    call skip_spaces
    cmp byte [si], 0
    je rename_usage

    mov di, fat_name_buffer_2
    call format_fat_filename
    jnc bad_filename

    call skip_token
    call skip_spaces
    cmp byte [si], 0
    jne rename_usage

    mov di, fat_name_buffer
    call find_file_by_name
    jnc file_not_found

    mov ax, [entry_sector_lba]
    mov [rename_sector_lba], ax
    mov ax, [entry_offset]
    mov [rename_entry_offset], ax

    mov di, fat_name_buffer_2
    call find_file_by_name
    jc rename_target_exists

    mov ax, [rename_sector_lba]
    mov bx, sector_buffer
    call read_sector_lba
    jc disk_error_shell

    mov di, sector_buffer
    add di, [rename_entry_offset]
    mov si, fat_name_buffer_2
    mov cx, 11
    rep movsb

    mov ax, [rename_sector_lba]
    mov bx, sector_buffer
    call write_sector_lba
    jc disk_error_shell

    mov si, rename_success_msg
    call print_string
    jmp shell_loop

.do_delete:
    mov si, input_buffer + 6
    call skip_spaces
    cmp byte [si], 0
    je delete_usage

    mov di, fat_name_buffer
    call format_fat_filename
    jnc bad_filename

    call skip_token
    call skip_spaces
    cmp byte [si], 0
    jne delete_usage

    call find_file
    jnc file_not_found

    mov ax, [file_first_cluster]
    mov [delete_first_cluster], ax

    mov ax, [entry_sector_lba]
    mov bx, sector_buffer
    call read_sector_lba
    jc disk_error_shell

    mov di, sector_buffer
    add di, [entry_offset]
    mov byte [di], 0xE5

    mov ax, [entry_sector_lba]
    mov bx, sector_buffer
    call write_sector_lba
    jc disk_error_shell

    mov ax, [delete_first_cluster]
    cmp ax, 2
    jb .delete_done
    call free_cluster_chain
    jc disk_error_shell

.delete_done:
    mov si, delete_success_msg
    call print_string
    jmp shell_loop

unknown_command:
    mov si, unknown_msg
    call print_string
    jmp shell_loop

echo_usage:
    mov si, echo_usage_msg
    call print_string
    jmp shell_loop

type_usage:
    mov si, type_usage_msg
    call print_string
    jmp shell_loop

rename_usage:
    mov si, rename_usage_msg
    call print_string
    jmp shell_loop

delete_usage:
    mov si, delete_usage_msg
    call print_string
    jmp shell_loop

bad_filename:
    mov si, bad_filename_msg
    call print_string
    jmp shell_loop

file_not_found:
    mov si, file_not_found_msg
    call print_string
    jmp shell_loop

rename_target_exists:
    mov si, rename_target_exists_msg
    call print_string
    jmp shell_loop

disk_error_shell:
    mov si, disk_error_msg
    call print_string
    jmp shell_loop

print_string:
    lodsb
    test al, al
    jz .done
    call print_char
    jmp print_string
.done:
    ret

print_char:
    push bx
    mov ah, 0x0E
    mov bh, 0x00
    mov bl, 0x1E
    int 0x10
    pop bx
    ret

print_newline:
    mov al, 0x0D
    call print_char
    mov al, 0x0A
    call print_char
    ret

print_space:
    mov al, ' '
    call print_char
    ret

print_word_decimal:
    pusha
    cmp ax, 0
    jne .convert
    mov al, '0'
    call print_char
    jmp .done

.convert:
    mov bx, 10
    xor cx, cx
.loop:
    xor dx, dx
    div bx
    push dx
    inc cx
    test ax, ax
    jnz .loop

.emit:
    pop dx
    add dl, '0'
    mov al, dl
    call print_char
    loop .emit

.done:
    popa
    ret

read_line:
    mov di, input_buffer
    xor cx, cx

.read_key:
    xor ah, ah
    int 0x16

    cmp al, 0x0D
    je .done
    cmp al, 0x08
    je .backspace
    cmp al, ' '
    jb .read_key
    cmp cx, INPUT_MAX - 1
    jae .read_key

    stosb
    inc cx
    call print_char
    jmp .read_key

.backspace:
    cmp cx, 0
    je .read_key
    dec di
    dec cx
    mov al, 0x08
    call print_char
    mov al, ' '
    call print_char
    mov al, 0x08
    call print_char
    jmp .read_key

.done:
    mov al, 0
    stosb
    call print_newline
    ret

uppercase_string:
    mov di, si
.loop:
    mov al, [di]
    test al, al
    jz .done
    cmp al, 'a'
    jb .next
    cmp al, 'z'
    ja .next
    sub byte [di], 32
.next:
    inc di
    jmp .loop
.done:
    ret

strings_equal:
.loop:
    mov al, [si]
    mov ah, [di]
    cmp al, ah
    jne .not_equal
    test al, al
    je .equal
    inc si
    inc di
    jmp .loop
.not_equal:
    clc
    ret
.equal:
    stc
    ret

starts_with:
.loop:
    mov al, [di]
    test al, al
    jz .matched
    cmp al, [si]
    jne .not_matched
    inc si
    inc di
    jmp .loop
.not_matched:
    clc
    ret
.matched:
    stc
    ret

skip_spaces:
.loop:
    cmp byte [si], ' '
    jne .done
    inc si
    jmp .loop
.done:
    ret

skip_token:
.loop:
    mov al, [si]
    test al, al
    jz .done
    cmp al, ' '
    je .done
    inc si
    jmp .loop
.done:
    ret

clear_screen:
    mov ax, 0x0003
    int 0x10
    mov ax, 0x0600
    mov bh, 0x1E
    mov cx, 0x0000
    mov dx, 0x184F
    int 0x10
    mov ah, 0x02
    mov bh, 0x00
    mov dx, 0x0000
    int 0x10
    ret

format_fat_filename:
    push si
    push di
    push bx
    push cx

    mov bx, di
    mov cx, 11
    mov al, ' '
.fill:
    mov [di], al
    inc di
    loop .fill

    xor ch, ch
    xor cl, cl
    mov byte [parse_state], 0

.next_char:
    mov al, [si]
    test al, al
    jz .finish
    cmp al, ' '
    je .finish
    cmp al, '.'
    je .dot
    cmp al, 0x21
    jb .fail

    cmp byte [parse_state], 0
    jne .store_ext

    cmp ch, 8
    jae .fail
    mov di, bx
    xor ah, ah
    mov al, ch
    add di, ax
    mov al, [si]
    mov [di], al
    inc ch
    inc si
    jmp .next_char

.store_ext:
    cmp cl, 3
    jae .fail
    mov di, bx
    xor ah, ah
    mov al, cl
    add di, 8
    add di, ax
    mov al, [si]
    mov [di], al
    inc cl
    inc si
    jmp .next_char

.dot:
    cmp byte [parse_state], 0
    jne .fail
    cmp ch, 0
    je .fail
    mov byte [parse_state], 1
    inc si
    jmp .next_char

.finish:
    cmp ch, 0
    je .fail
    stc
    jmp .done

.fail:
    clc

.done:
    pop cx
    pop bx
    pop di
    pop si
    ret

list_files:
    push ax
    push bx
    push cx
    push dx
    push si

    mov word [file_count], 0
    mov ax, ROOT_DIR_LBA
    mov cx, ROOT_DIR_SECTORS

.sector_loop:
    push ax
    push cx
    mov bx, sector_buffer
    call read_sector_lba
    jc .disk_error

    mov si, sector_buffer
    mov dx, 16

.entry_loop:
    mov al, [si]
    cmp al, 0x00
    je .done_listing
    cmp al, 0xE5
    je .next_entry

    mov al, [si + 11]
    cmp al, 0x0F
    je .next_entry
    test al, 0x08
    jnz .next_entry

    call print_dir_entry
    inc word [file_count]

.next_entry:
    add si, 32
    dec dx
    jnz .entry_loop

    pop cx
    pop ax
    inc ax
    dec cx
    jnz .sector_loop
    jmp .after_listing

.done_listing:
    pop cx
    pop ax

.after_listing:
    cmp word [file_count], 0
    jne .newline
    mov si, empty_dir_msg
    call print_string
    jmp .finish

.newline:
    call print_newline
    jmp .finish

.disk_error:
    pop cx
    pop ax
    mov si, disk_error_msg
    call print_string

.finish:
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

print_dir_entry:
    push ax
    push bx
    push cx
    push dx
    push si

    mov bx, si
    mov cx, 8
.name_loop:
    mov al, [bx]
    cmp al, ' '
    je .after_name
    call print_char
    inc bx
    loop .name_loop

.after_name:
    mov al, [si + 8]
    cmp al, ' '
    je .print_size
    mov al, '.'
    call print_char
    mov cx, 3
    mov bx, si
    add bx, 8
.ext_loop:
    mov al, [bx]
    cmp al, ' '
    je .print_size
    call print_char
    inc bx
    loop .ext_loop

.print_size:
    call print_space
    call print_space
    mov ax, [si + 28]
    call print_word_decimal
    mov si, bytes_suffix
    call print_string
    call print_newline

    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

find_file:
    mov di, fat_name_buffer

find_file_by_name:
    push ax
    push bx
    push cx
    push dx
    push si
    push di

    mov [find_name_ptr], di
    mov ax, ROOT_DIR_LBA
    mov cx, ROOT_DIR_SECTORS

.sector_loop:
    mov [search_sector_lba], ax
    push ax
    push cx
    mov bx, sector_buffer
    call read_sector_lba
    jc .not_found

    mov si, sector_buffer
    mov dx, 16

.entry_loop:
    mov al, [si]
    cmp al, 0x00
    je .not_found_pop
    cmp al, 0xE5
    je .next_entry
    mov al, [si + 11]
    cmp al, 0x0F
    je .next_entry
    test al, 0x08
    jnz .next_entry

    push si
    mov di, [find_name_ptr]
    mov cx, 11
    repe cmpsb
    pop si
    je .found

.next_entry:
    add si, 32
    dec dx
    jnz .entry_loop

    pop cx
    pop ax
    inc ax
    dec cx
    jnz .sector_loop
    jmp .not_found_done

.found:
    mov ax, [si + 26]
    mov [file_first_cluster], ax
    mov ax, [si + 28]
    mov [file_size], ax
    mov ax, [search_sector_lba]
    mov [entry_sector_lba], ax
    mov ax, si
    sub ax, sector_buffer
    mov [entry_offset], ax
    pop cx
    pop ax
    stc
    jmp .finish

.not_found_pop:
    pop cx
    pop ax

.not_found_done:
.not_found:
    clc

.finish:
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

type_file:
    push ax
    push bx
    push cx
    push dx
    push si

    mov dx, [file_size]
    mov ax, [file_first_cluster]
    mov [current_cluster], ax

    cmp dx, 0
    je .done

.cluster_loop:
    cmp word [current_cluster], 0xFF8
    jae .done

    mov ax, [current_cluster]
    call cluster_to_lba
    mov bx, sector_buffer
    call read_sector_lba
    jc .read_error

    mov cx, dx
    cmp cx, SECTOR_SIZE
    jbe .set_count
    mov cx, SECTOR_SIZE

.set_count:
    mov [bytes_to_print], cx
    mov si, sector_buffer

.print_loop:
    lodsb
    call print_char
    dec word [bytes_to_print]
    jnz .print_loop

    sub dx, cx
    jz .done

    mov ax, [current_cluster]
    call get_next_cluster
    mov [current_cluster], ax
    jmp .cluster_loop

.read_error:
    mov si, disk_error_msg
    call print_string
    jmp .finish

.done:
    call print_newline
    call print_newline

.finish:
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

cluster_to_lba:
    sub ax, 2
    add ax, DATA_START_LBA
    ret

get_next_cluster:
    push bx
    push cx
    push dx
    push si

    mov dx, ax
    mov bx, ax
    shr bx, 1
    add bx, ax

    mov ax, bx
    shr ax, 9
    add ax, FAT1_LBA
    mov bx, fat_buffer
    call read_sector_lba
    jc .error

    inc ax
    mov bx, fat_buffer + SECTOR_SIZE
    call read_sector_lba
    jc .error

    mov bx, dx
    shr bx, 1
    add bx, dx
    and bx, 0x01FF
    mov si, fat_buffer
    add si, bx
    mov ax, [si]
    test dx, 1
    jz .even
    shr ax, 4
    jmp .done

.even:
    and ax, 0x0FFF
    jmp .done

.error:
    mov ax, 0x0FFF

.done:
    pop si
    pop dx
    pop cx
    pop bx
    ret

set_fat_entry:
    push bx
    push cx
    push dx
    push si
    push di

    mov di, ax
    mov bx, ax
    shr bx, 1
    add bx, ax

    mov ax, bx
    shr ax, 9
    add ax, FAT1_LBA
    mov [fat_sector_lba], ax

    mov bx, fat_buffer
    call read_sector_lba
    jc .error

    inc ax
    mov [fat_sector_lba_2], ax
    mov bx, fat_buffer + SECTOR_SIZE
    call read_sector_lba
    jc .error

    mov bx, di
    shr bx, 1
    add bx, di
    and bx, 0x01FF
    mov si, fat_buffer
    add si, bx
    mov ax, [si]
    test di, 1
    jz .even
    and ax, 0x000F
    mov dx, cx
    and dx, 0x0FFF
    shl dx, 4
    or ax, dx
    jmp .store

.even:
    and ax, 0xF000
    mov dx, cx
    and dx, 0x0FFF
    or ax, dx

.store:
    mov [si], ax

    mov ax, [fat_sector_lba]
    mov bx, fat_buffer
    call write_sector_lba
    jc .error

    mov ax, [fat_sector_lba_2]
    mov bx, fat_buffer + SECTOR_SIZE
    call write_sector_lba
    jc .error

    mov ax, [fat_sector_lba]
    add ax, SECTORS_PER_FAT
    mov bx, fat_buffer
    call write_sector_lba
    jc .error

    mov ax, [fat_sector_lba_2]
    add ax, SECTORS_PER_FAT
    mov bx, fat_buffer + SECTOR_SIZE
    call write_sector_lba
    jc .error

    clc
    jmp .done

.error:
    stc

.done:
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    ret

free_cluster_chain:
    push ax
    push bx
    push cx
    push dx

.loop:
    cmp ax, 2
    jb .success
    cmp ax, 0xFF8
    jae .success
    mov [delete_current_cluster], ax
    call get_next_cluster
    mov bx, ax
    mov ax, [delete_current_cluster]
    xor cx, cx
    call set_fat_entry
    jc .failure
    mov ax, bx
    jmp .loop

.success:
    clc
    jmp .done

.failure:
    stc

.done:
    pop dx
    pop cx
    pop bx
    pop ax
    ret

read_sector_lba:
    push ax
    push bx
    push cx
    push dx
    push si

    xor dx, dx
    mov cx, SECTORS_PER_TRACK
    div cx
    mov cl, dl
    inc cl

    xor dx, dx
    mov si, HEADS
    div si
    mov dh, dl
    mov ch, al
    mov dl, [boot_drive]

    mov ah, 0x02
    mov al, 0x01
    int 0x13
    jnc .success

    mov ah, 0x00
    int 0x13
    mov ah, 0x02
    mov al, 0x01
    int 0x13
    jc .failure

.success:
    clc
    jmp .done

.failure:
    stc

.done:
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

write_sector_lba:
    push ax
    push bx
    push cx
    push dx
    push si

    xor dx, dx
    mov cx, SECTORS_PER_TRACK
    div cx
    mov cl, dl
    inc cl

    xor dx, dx
    mov si, HEADS
    div si
    mov dh, dl
    mov ch, al
    mov dl, [boot_drive]

    mov ah, 0x03
    mov al, 0x01
    int 0x13
    jnc .success

    mov ah, 0x00
    int 0x13
    mov ah, 0x03
    mov al, 0x01
    int 0x13
    jc .failure

.success:
    clc
    jmp .done

.failure:
    stc

.done:
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

banner db "FirstOS", 0x0D, 0x0A
       db "A tiny MikeOS-style shell with a real FAT12 floppy.", 0x0D, 0x0A
       db "Type HELP to get started.", 0x0D, 0x0A, 0x0D, 0x0A, 0
prompt db "> ", 0
help_msg db "HELP   - show the command list", 0x0D, 0x0A
         db "CLS    - clear the screen", 0x0D, 0x0A
         db "VER    - show the OS version", 0x0D, 0x0A
         db "REBOOT - restart the machine", 0x0D, 0x0A
         db "LIST   - list files from the FAT12 root directory", 0x0D, 0x0A
         db "TYPE   - print a file, for example TYPE README.TXT", 0x0D, 0x0A
         db "RENAME - rename a file, for example RENAME OLD.TXT NEW.TXT", 0x0D, 0x0A
         db "DELETE - remove a file, for example DELETE HELLO.TXT", 0x0D, 0x0A
         db "ABOUT  - describe this tiny OS", 0x0D, 0x0A
         db "ECHO   - print text back to the screen", 0x0D, 0x0A
         db 0x0D, 0x0A, 0
version_msg db "FirstOS version 0.2", 0x0D, 0x0A, 0x0D, 0x0A, 0
reboot_msg db "Rebooting...", 0x0D, 0x0A, 0
about_msg db "FirstOS now uses a real FAT12 floppy image with root-directory files.", 0x0D, 0x0A
         db "There are ten commands.", 0x0D, 0x0A
         db 0x0D, 0x0A, 0
echo_usage_msg db "Usage: ECHO your text here", 0x0D, 0x0A, 0x0D, 0x0A, 0
type_usage_msg db "Usage: TYPE README.TXT", 0x0D, 0x0A, 0x0D, 0x0A, 0
rename_usage_msg db "Usage: RENAME OLD.TXT NEW.TXT", 0x0D, 0x0A, 0x0D, 0x0A, 0
delete_usage_msg db "Usage: DELETE HELLO.TXT", 0x0D, 0x0A, 0x0D, 0x0A, 0
bad_filename_msg db "Use an 8.3 filename like README.TXT", 0x0D, 0x0A, 0x0D, 0x0A, 0
file_not_found_msg db "File not found.", 0x0D, 0x0A, 0x0D, 0x0A, 0
rename_target_exists_msg db "A file with that name already exists.", 0x0D, 0x0A, 0x0D, 0x0A, 0
rename_success_msg db "File renamed.", 0x0D, 0x0A, 0x0D, 0x0A, 0
delete_success_msg db "File deleted.", 0x0D, 0x0A, 0x0D, 0x0A, 0
empty_dir_msg db "No files found.", 0x0D, 0x0A, 0x0D, 0x0A, 0
disk_error_msg db "Disk read failed.", 0x0D, 0x0A, 0x0D, 0x0A, 0
unknown_msg db "Unknown command. Type HELP.", 0x0D, 0x0A, 0x0A, 0
bytes_suffix db " bytes", 0

cmd_help db "HELP", 0
cmd_cls db "CLS", 0
cmd_ver db "VER", 0
cmd_reboot db "REBOOT", 0
cmd_list db "LIST", 0
cmd_type db "TYPE", 0
cmd_rename db "RENAME", 0
cmd_delete db "DELETE", 0
cmd_about db "ABOUT", 0
cmd_echo db "ECHO", 0

boot_drive db 0
parse_state db 0
file_count dw 0
file_first_cluster dw 0
file_size dw 0
current_cluster dw 0
bytes_to_print dw 0
entry_sector_lba dw 0
entry_offset dw 0
rename_sector_lba dw 0
rename_entry_offset dw 0
search_sector_lba dw 0
find_name_ptr dw 0
delete_first_cluster dw 0
delete_current_cluster dw 0
fat_sector_lba dw 0
fat_sector_lba_2 dw 0
fat_name_buffer times 11 db 0
fat_name_buffer_2 times 11 db 0
input_buffer times INPUT_MAX db 0
sector_buffer times SECTOR_SIZE db 0
fat_buffer times SECTOR_SIZE * 2 db 0
