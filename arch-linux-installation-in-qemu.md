# Install Arch Linux In Qemu

## 1. Create System Disk

```sh
qemu-img create -f qcow2 img1.qcow2 4G
```

## 2. Run The Cdrom Img In Terminal

- Basic Start:

  ```sh
  qemu-system-x86_64 -cdrom archlinux-x86_64.iso \
                     -drive file=img1.qcow2,format=qcow2
  ```

- Using KVM Mode:

  ```sh
  qemu-system-x86_64 -accel kvm \
                      -m 8G \
                      -smp 4 \
                      -drive file=img1.qcow2,format=qcow2,format=qcow2 \
                      -cdrom archlinux-x86_64.iso \
                      -boot d
  ```

- Using EFI (new BIOS):

  ```sh
  qemu-system-x86_64 -accel kvm \
                     -m 8G \
                     -smp 4 \
                     -drive file=img1.qcow2,format=qcow2 \
                     -bios /usr/share/edk2/x64/OVMF.fd \
                     -cdrom archlinux-x86_64.iso -boot d
  ```

## 4. Start The System When Installed

  ```sh
  qemu-system-x86_64 -accel kvm \
                     -m 8G \
                     -smp 4 \
                     -drive file=img1.qcow2,format=qcow2 \
                     -vga qxl \
                     -bios /usr/share/edk2/x64/OVMF.fd
  ```

## Additionaly, Final Command Using NVME Drive

```sh
qemu-system-x86_64 \
    -machine q35 \
    -accel kvm \
    -m 8G \
    -smp 4 \
    -vga qxl \
    -drive file=img1.qcow2,format=qcow2,if=none,id=nvme0 \
    -device nvme,drive=nvme0,serial=deadbeef \
    -drive if=pflash,format=raw,readonly=on,file=/usr/share/edk2/x64/OVMF_CODE.4m.fd \
    -drive if=pflash,format=raw,file=/usr/share/edk2/x64/OVMF_VARS.4m.fd \
    -cdrom archlinux-x86_64.iso
```

> Note: Install `xf86-video-qxl`.
