BUILD_DIR := build
BOOT_BIN := $(BUILD_DIR)/boot.bin
KERNEL_BIN := $(BUILD_DIR)/kernel.bin
IMAGE := $(BUILD_DIR)/firstos.img
FS_DIR := fs

.PHONY: all run clean

all: $(IMAGE)

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

$(BOOT_BIN): boot.asm | $(BUILD_DIR)
	nasm -f bin boot.asm -o $(BOOT_BIN)

$(KERNEL_BIN): kernel.asm | $(BUILD_DIR)
	nasm -f bin kernel.asm -o $(KERNEL_BIN)

$(IMAGE): $(BOOT_BIN) $(KERNEL_BIN)
	python3 build_image.py $(BOOT_BIN) $(KERNEL_BIN) $(FS_DIR) $(IMAGE)

run: $(IMAGE)
	qemu-system-i386 -drive format=raw,if=floppy,file=$(IMAGE)

clean:
	rm -rf $(BUILD_DIR)
