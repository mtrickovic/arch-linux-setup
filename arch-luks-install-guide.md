# Arch Linux Installation Guide
## Encrypted Root Partition with systemd-boot

**Target Configuration:**
- linux-hardened kernel
- LUKS encrypted root partition
- systemd in initramfs
- ext4 filesystem (simpler, better performance)
- systemd-boot bootloader
- Hardened kernel parameters

---

## Table of Contents

1. [Pre-Installation Setup](#pre-installation-setup)
2. [Disk Partitioning](#disk-partitioning)
3. [LUKS Encryption Setup](#luks-encryption-setup)
4. [Filesystem Creation](#filesystem-creation)
5. [Base System Installation](#base-system-installation)
6. [System Configuration](#system-configuration)
7. [Bootloader Configuration](#bootloader-configuration)
8. [Initramfs Configuration](#initramfs-configuration)
9. [ESP Security](#esp-security)
10. [Troubleshooting](#troubleshooting)

---

## Pre-Installation Setup

### Boot the Installation Media

1. Boot from Arch Linux USB
2. Verify boot mode (should be UEFI):
```bash
ls /sys/firmware/efi/efivars
# If this directory exists, you're in UEFI mode
```

3. Connect to internet:
```bash
# For wired connection
dhcpcd

# For WiFi
iwctl
station wlan0 connect "YourSSID"
```

4. Update system clock:
```bash
timedatectl set-ntp true
```

---

## Disk Partitioning

### Identify Your Disk
```bash
lsblk
# Identify your target disk (e.g., /dev/sda, /dev/nvme0n1, /dev/vda)
```

**For this guide, we'll use `/dev/sda` - replace with your actual disk!**

### Create Partitions

```bash
gdisk /dev/sda
```

#### Partition Layout:

| Partition | Size | Type | Purpose |
|-----------|------|------|---------|
| /dev/sda1 | 512M | EF00 (EFI System) | ESP/Boot |
| /dev/sda2 | Rest | 8300 (Linux filesystem) | Encrypted Root |

#### gdisk Commands:
```
o          # Create new GPT partition table
n          # New partition
[Enter]    # Partition 1
[Enter]    # First sector (default)
+512M      # Last sector
EF00       # EFI System partition type

n          # New partition
[Enter]    # Partition 2
[Enter]    # First sector (default)
[Enter]    # Last sector (use rest of disk)
8300       # Linux filesystem (default)

w          # Write changes
```

### Verify Partitions
```bash
lsblk /dev/sda
# Should show:
# sda
# ├─sda1  512M
# └─sda2  [remaining space]
```

---

## LUKS Encryption Setup

### Create Encrypted Container

```bash
cryptsetup luksFormat /dev/sda2
# Type YES (in capitals)
# Enter a strong passphrase (you'll need this on every boot!)
```

### Open the Encrypted Container

```bash
cryptsetup open /dev/sda2 cryptroot
# Enter your passphrase
```

**Verify:**
```bash
ls /dev/mapper/
# Should show: cryptroot
```

### Get the LUKS UUID (CRITICAL - SAVE THIS!)

```bash
blkid /dev/sda2 -o value -s UUID
```

**Write this UUID down! You'll need it for bootloader configuration.**

Example output: `11304311-217e-404c-0eac-c8fa5f9c8053`

---

## Filesystem Creation

### Format ESP Partition
```bash
mkfs.fat -F32 /dev/sda1
```

### Format Root Partition
```bash
mkfs.ext4 /dev/mapper/cryptroot
```

### Mount Filesystems
```bash
# Mount root
mount /dev/mapper/cryptroot /mnt

# Create and mount ESP
mkdir -p /mnt/boot
mount /dev/sda1 /mnt/boot
```

**Verify:**
```bash
lsblk
# Should show both mounted at /mnt and /mnt/boot
```

---

## Base System Installation

### Install Essential Packages
```bash
pacstrap -K /mnt base linux-hardened linux-firmware \
  base-devel \
  networkmanager \
  nano vim \
  man-db man-pages \
  cryptsetup \
  intel-ucode  # Use amd-ucode for AMD CPUs
```

### Generate fstab
```bash
genfstab -U /mnt >> /mnt/etc/fstab
```

**Verify:**
```bash
cat /mnt/etc/fstab
# Should contain entries for / and /boot
```

---

## System Configuration

### Chroot into New System
```bash
arch-chroot /mnt
```

### Set Timezone
```bash
ln -sf /usr/share/zoneinfo/Europe/Vienna /mnt/etc/localtime
hwclock --systohc
```

### Localization
```bash
# Edit locale.gen
nano /etc/locale.gen
# Uncomment: en_US.UTF-8 UTF-8

# Generate locales
locale-gen

# Set locale
echo "LANG=en_US.UTF-8" > /etc/locale.conf
```

### Network Configuration
```bash
# Set hostname
echo "yourhostname" > /etc/hostname

# Edit hosts file
nano /etc/hosts
```

Add:
```
127.0.0.1   localhost
::1         localhost
127.0.1.1   yourhostname.localdomain yourhostname
```

### Enable NetworkManager
```bash
systemctl enable NetworkManager
```

### Set Root Password
```bash
passwd
```

---

## Initramfs Configuration

### Edit mkinitcpio.conf

```bash
nano /etc/mkinitcpio.conf
```

**CRITICAL: Configure HOOKS correctly!**

Change the HOOKS line to:
```bash
HOOKS=(base systemd autodetect microcode modconf kms keyboard sd-vconsole block sd-encrypt filesystems fsck)
```

**Key Points:**
- `systemd` instead of `udev` (we're using systemd-based initramfs)
- `sd-encrypt` instead of `encrypt` (systemd's LUKS unlock)
- `keyboard` and `sd-vconsole` BEFORE `sd-encrypt` (so you can type password)
- Order matters!

### Generate Initramfs
```bash
mkinitcpio -P
```

**Verify:**
```bash
ls -lh /boot/initramfs-linux-hardened*
# Should show two files:
# initramfs-linux-hardened.img
# initramfs-linux-hardened-fallback.img
```

---

## Bootloader Configuration

### Install systemd-boot
```bash
bootctl install
```

### Get Your LUKS UUID Again
```bash
blkid /dev/sda2 -o value -s UUID
```

**Example: `11304311-217e-404c-0eac-c8fa5f9c8053`**

### Create Bootloader Entry
```bash
nano /boot/loader/entries/arch-hardened.conf
```

**Add the following (replace UUID with yours!):**

```
title   Arch Linux Hardened
linux   /vmlinuz-linux-hardened
initrd  /intel-ucode.img
initrd  /initramfs-linux-hardened.img
options rd.luks.name=11304311-217e-404c-0eac-c8fa5f9c8053=cryptroot root=/dev/mapper/cryptroot rw
```

**CRITICAL rd.luks.name Parameter Breakdown:**

```
rd.luks.name=<LUKS-UUID>=<mapper-name>
             └─────┬────┘  └────┬─────┘
                   │            └─ Name for /dev/mapper/cryptroot
                   └─ UUID from blkid /dev/sda2 (the encrypted partition)
```

### Configure Bootloader Defaults
```bash
nano /boot/loader/loader.conf
```

Add:
```
default arch-hardened.conf
timeout 3
console-mode max
editor no
```

**Important:** `editor no` prevents editing kernel parameters at boot (security hardening)

### Add Hardened Kernel Parameters

Edit your boot entry again:
```bash
nano /boot/loader/entries/arch-hardened.conf
```

Expand the options line:
```
options rd.luks.name=YOUR-UUID=cryptroot root=/dev/mapper/cryptroot rw lockdown=confidentiality module.sig_enforce=1 slab_nomerge init_on_alloc=1 init_on_free=1 page_alloc.shuffle=1 randomize_kstack_offset=on vsyscall=none debugfs=off
```

**Hardening Parameters Explained:**
- `lockdown=confidentiality` - Restrict kernel features that could leak data
- `module.sig_enforce=1` - Only load signed kernel modules
- `slab_nomerge` - Prevent heap exploit techniques
- `init_on_alloc=1 init_on_free=1` - Zero memory on allocation/free
- `page_alloc.shuffle=1` - Randomize page allocator
- `randomize_kstack_offset=on` - Randomize kernel stack
- `vsyscall=none` - Disable legacy vsyscall
- `debugfs=off` - Disable debug filesystem

---

## ESP Security

The ESP (EFI System Partition) at `/boot` must be unencrypted for UEFI firmware to read it. However, we can limit access.

### Set Restrictive Permissions

```bash
# Restrict /boot directory
chmod 700 /boot
chown root:root /boot

# Restrict kernel and initramfs
chmod 600 /boot/vmlinuz-linux-hardened
chmod 600 /boot/initramfs-linux-hardened.img
chmod 600 /boot/initramfs-linux-hardened-fallback.img
chmod 600 /boot/intel-ucode.img
```

### Create Maintenance Script

```bash
nano /usr/local/bin/secure-boot-permissions
```

Add:
```bash
#!/bin/bash
# Secure ESP permissions after kernel updates

chmod 700 /boot
chmod 600 /boot/vmlinuz-*
chmod 600 /boot/initramfs-*
chmod 600 /boot/*-ucode.img
chmod -R 700 /boot/EFI
echo "ESP permissions secured"
```

Make executable:
```bash
chmod +x /usr/local/bin/secure-boot-permissions
```

### Pacman Hook for Automatic Securing

```bash
mkdir -p /etc/pacman.d/hooks
nano /etc/pacman.d/hooks/secure-esp.hook
```

Add:
```
[Trigger]
Operation = Install
Operation = Upgrade
Type = Path
Target = usr/lib/modules/*/vmlinuz
Target = boot/*

[Action]
Description = Securing ESP permissions...
When = PostTransaction
Exec = /usr/local/bin/secure-boot-permissions
```

### ESP Security Limitations

**Important to understand:**

1. **FAT32 limitations** - ESP uses FAT32, which doesn't fully support Unix permissions
2. **UEFI reads before Linux** - Firmware accesses files before permission checks
3. **Physical access** - Anyone with physical access can read ESP by booting from USB
4. **Best protection: Secure Boot** - Use UEFI Secure Boot with your own keys for real integrity protection

**The permissions above protect against:**
- Accidental modification by non-root users
- Some local privilege escalation attempts
- Casual snooping on a running system

**They do NOT protect against:**
- Attackers with physical access
- Sophisticated boot-time attacks
- Cold boot attacks

**For maximum security, also implement:**
- UEFI Secure Boot with custom keys
- BIOS/UEFI password
- TPM-based measured boot
- Physical security for the machine

---

## Final Steps

### Create User Account
```bash
useradd -m -G wheel -s /bin/bash yourusername
passwd yourusername
```

### Configure sudo
```bash
EDITOR=nano visudo
```

Uncomment:
```
%wheel ALL=(ALL:ALL) ALL
```

### Exit and Reboot
```bash
exit
umount -R /mnt
reboot
```

**Remove installation media!**

---

## Troubleshooting

### Boot Fails with "A start job is running for /dev/mapper/cryptroot"

**Cause:** Wrong UUID in boot entry or initramfs misconfiguration

**Solution:**
1. Boot from installation media
2. Open LUKS: `cryptsetup open /dev/sda2 cryptroot`
3. Mount: `mount /dev/mapper/cryptroot /mnt && mount /dev/sda1 /mnt/boot`
4. Chroot: `arch-chroot /mnt`
5. Verify UUID:
   ```bash
   blkid /dev/sda2
   # Compare with /boot/loader/entries/arch-hardened.conf
   ```
6. If wrong, fix the boot entry
7. Regenerate initramfs: `mkinitcpio -P`
8. Reboot

### No Password Prompt at Boot

**Cause:** Missing `sd-encrypt` hook or wrong HOOKS order

**Solution:**
1. Boot installation media and chroot (as above)
2. Edit `/etc/mkinitcpio.conf`
3. Ensure HOOKS line has:
   ```
   HOOKS=(base systemd autodetect microcode modconf kms keyboard sd-vconsole block sd-encrypt filesystems fsck)
   ```
4. Regenerate: `mkinitcpio -P`
5. Reboot

### "cryptroot: device not found" Error

**Cause:** Wrong UUID or LUKS partition not detected

**Solution:**
1. Boot installation media
2. Check LUKS partition:
   ```bash
   blkid | grep crypto_LUKS
   ```
3. Verify this UUID matches `rd.luks.name=UUID=...` in boot entry
4. The UUID must be from the **encrypted partition** (/dev/sda2), NOT from /dev/mapper/cryptroot

### Emergency Shell Without Errors

**Cause:** Usually missing filesystem support

**Solution:**
1. In emergency shell:
   ```bash
   lsblk
   # Check if /dev/mapper/cryptroot exists
   
   mount /dev/mapper/cryptroot /sysroot
   # If this fails, note the error
   ```
2. Boot installation media, chroot
3. If ext4 mount failed, reinstall filesystem tools:
   ```bash
   pacman -S e2fsprogs
   mkinitcpio -P
   ```

---

## Verification Checklist

Before rebooting, verify:

- [ ] LUKS partition created on /dev/sda2
- [ ] ESP formatted as FAT32 on /dev/sda1
- [ ] Filesystems mounted during installation
- [ ] LUKS UUID saved and used in boot entry
- [ ] initramfs HOOKS include: `systemd`, `keyboard`, `sd-vconsole`, `sd-encrypt`
- [ ] initramfs generated successfully
- [ ] Boot entry created with correct `rd.luks.name=UUID=mapper-name`
- [ ] Bootloader installed with `bootctl install`
- [ ] NetworkManager enabled
- [ ] Root password set
- [ ] User account created

---

## Quick Reference Card

### Critical UUIDs

```bash
# Get LUKS UUID (for bootloader)
blkid /dev/sda2 -o value -s UUID

# Get filesystem UUID (for fstab - auto-generated)
blkid /dev/mapper/cryptroot -o value -s UUID
```

### Boot Entry Format

```
title   Arch Linux Hardened
linux   /vmlinuz-linux-hardened
initrd  /intel-ucode.img
initrd  /initramfs-linux-hardened.img
options rd.luks.name=<LUKS-UUID>=cryptroot root=/dev/mapper/cryptroot rw
```

### mkinitcpio HOOKS

```
HOOKS=(base systemd autodetect microcode modconf kms keyboard sd-vconsole block sd-encrypt filesystems fsck)
```

### Common Commands

```bash
# Unlock LUKS manually
cryptsetup open /dev/sda2 cryptroot

# Mount for recovery
mount /dev/mapper/cryptroot /mnt
mount /dev/sda1 /mnt/boot

# Chroot
arch-chroot /mnt

# Regenerate initramfs
mkinitcpio -P

# Update bootloader
bootctl update
```

---

## Additional Resources

- Arch Wiki LUKS: https://wiki.archlinux.org/title/Dm-crypt
- Arch Wiki Installation: https://wiki.archlinux.org/title/Installation_guide
- Arch Wiki systemd-boot: https://wiki.archlinux.org/title/Systemd-boot
- Arch Wiki Security: https://wiki.archlinux.org/title/Security

---

**Document Version:** 1.0  
**Last Updated:** November 2025  
**Author:** Installation Guide for Encrypted Arch Linux

---

## Notes

- This guide uses **ext4** for simplicity and performance
- For **btrfs**, you'll need to add subvolume parameters
- Always test in a VM first before installing on real hardware
- Keep installation media handy for recovery
- Document your LUKS passphrase securely (but separately from the system)

**Good luck with your installation!**