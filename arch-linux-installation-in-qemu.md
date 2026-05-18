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
                      -drive file=img1.cow,format=qcow2,format=qcow2 \
                      -cdrom archlinux-x86_64.iso \
                      -boot d
  ```

- Using EFI (new BIOS):

  ```sh
  qemu-system-x86_64 -accel kvm \
                     -m 8G \
                     -smp 4 \
                     -drive file=img1.cow,format=qcow2 \
                     -bios /usr/share/edk2/x64/OVMF.fd \
                     -cdrom archlinux-x86_64.iso -boot d
  ```

## 4. Start The System When Installed

  ```sh
  qemu-system-x86_64 -accel kvm \
                     -m 8G \
                     -smp 4 \
                     -drive file=img1.cow,format=qcow2 \
                     -bios /usr/share/edk2/x64/OVMF.fd
  ```
