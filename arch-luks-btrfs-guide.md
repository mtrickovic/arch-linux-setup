# Arch Linux Installation Guide
## LUKS Encryption + Btrfs Filesystem + systemd

**Complete Guide for Encrypted Arch Linux with Btrfs**

**Target Configuration:**
- linux-hardened kernel
- LUKS encrypted root partition
- Btrfs filesystem with subvolumes
- systemd in initramfs
- systemd-boot bootloader
- Hardened kernel parameters

**Document Version:** 2.0 - Btrfs Edition  
**Last Updated:** November 2025

---

## Table of Contents

1. [Understanding Btrfs](#understanding-btrfs)
2. [Pre-Installation Setup](#pre-installation-setup)
3. [Disk Partitioning](#disk-partitioning)
4. [LUKS Encryption Setup](#luks-encryption-setup)
5. [Btrfs Filesystem Creation](#btrfs-filesystem-creation)
6. [Subvolume Structure](#subvolume-structure)
7. [Base System Installation](#base-system-installation)
8. [System Configuration](#system-configuration)
9. [Initramfs Configuration](#initramfs-configuration)
10. [Bootloader Configuration](#bootloader-configuration)
11. [Btrfs Maintenance](#btrfs-maintenance)
12. [ESP Security](#esp-security)
13. [Troubleshooting](#troubleshooting)

---

## Understanding Btrfs

### What is Btrfs?

Btrfs (B-tree File System) is a modern copy-on-write (CoW) filesystem for Linux with advanced features.

### Key Btrfs Concepts

**Subvolumes:**
- Think of them as "internal partitions"
- Can be mounted independently
- Can have different mount options
- Can be snapshotted individually
- Example: separate subvolumes for root, home, and var

**Snapshots:**
- Instant, space-efficient copies of subvolumes
- Perfect for backing up before system updates
- Can be used to rollback your system
- Takes seconds to create, even for large filesystems

**Compression:**
- Transparent compression of data
- Saves disk space (often 20-40% reduction)
- Can improve performance on SSDs
- Options: zstd (recommended), lzo, zlib

**Copy-on-Write (CoW):**
- Modified data is written to new location
- Original data stays intact until overwritten
- Enables snapshots and better data integrity
- Can cause fragmentation over time

### Why Use Btrfs?

**Advantages:**
- Instant snapshots before system updates
- Easy rollback if updates break things
- Built-in compression saves space
- Subvolumes allow flexible layouts
- Data integrity through checksums
- No need for separate /home partition

**Considerations:**
- Slightly more complex than ext4
- Needs periodic maintenance (balancing, scrubbing)
- Can fragment over time (defrag needed)
- Uses more RAM than ext4

### Common Subvolume Layouts

**Standard Layout (we'll use this):**

SUBVOLUME | MOUNT POINT | PURPOSE
----------|-------------|--------
@ | / | Root filesystem
@home | /home | User home directories  
@var | /var | Variable data, logs
@tmp | /tmp | Temporary files
@snapshots | /.snapshots | Snapshot storage

**Why this structure?**
- Separate snapshots for different parts of system
- Exclude temporary data from snapshots
- Easier rollback of specific components

---

## Pre-Installation Setup

### Boot the Installation Media

STEP 1: Boot from Arch Linux USB

STEP 2: Verify UEFI boot mode

Command to verify UEFI mode:

    ls /sys/firmware/efi/efivars

Expected result: Directory exists and contains files

If directory doesn't exist, you're in BIOS mode (this guide requires UEFI)

STEP 3: Connect to internet

For wired connection:

    dhcpcd

For WiFi connection:

    iwctl
    
In iwctl prompt:

    station wlan0 connect "YourNetworkName"
    
Exit iwctl:

    exit

Verify internet connection:

    ping -c 3 archlinux.org

STEP 4: Update system clock

    timedatectl set-ntp true

Verify time is correct:

    timedatectl status

---

## Disk Partitioning

### Identify Your Disk

List all disks:

    lsblk

Common disk names:
- SATA/SSD: /dev/sda, /dev/sdb
- NVMe: /dev/nvme0n1, /dev/nvme1n1
- VirtualBox: /dev/vda

**IMPORTANT:** This guide uses /dev/nvme0n1 (NVMe SSD)

If your disk has a different name, replace /dev/nvme0n1 throughout this guide!

### Partition Layout

We will create TWO partitions:

PARTITION | SIZE | TYPE | PURPOSE
----------|------|------|--------
/dev/nvme0n1p1 | 512MB | EF00 | ESP/Boot (unencrypted)
/dev/nvme0n1p2 | Remaining | 8300 | LUKS encrypted root

**Note:** NVMe partitions use 'p' separator: nvme0n1p1, nvme0n1p2

### Create Partitions with gdisk

Launch gdisk:

    gdisk /dev/nvme0n1

**WARNING:** This will erase all data on the disk!

gdisk commands to execute:

Create new GPT table:

    o

Confirm with:

    Y

Create ESP partition (512MB):

    n
    [press Enter]  (partition number 1)
    [press Enter]  (first sector, default)
    +512M          (last sector, 512MB size)
    EF00           (EFI System partition type)

Create root partition (rest of disk):

    n
    [press Enter]  (partition number 2)
    [press Enter]  (first sector, default)
    [press Enter]  (last sector, use remaining space)
    8300           (Linux filesystem, default)

Write changes to disk:

    w

Confirm with:

    Y

### Verify Partitions

List partitions:

    lsblk /dev/nvme0n1

Expected output:

    NAME         SIZE TYPE
    nvme0n1      XXXG disk
    ├─nvme0n1p1  512M part
    └─nvme0n1p2  XXXG part

---

## LUKS Encryption Setup

### Create Encrypted Container

**CRITICAL:** Choose a STRONG passphrase. You'll need this on EVERY boot!

Format partition with LUKS:

    cryptsetup luksFormat /dev/nvme0n1p2

You will be asked:

    Are you sure? (Type 'yes' in capital letters): YES

Then enter your passphrase TWICE.

**Important:** This passphrase unlocks your entire system. Don't forget it!

### Open the Encrypted Container

Unlock the LUKS partition:

    cryptsetup open /dev/nvme0n1p2 cryptroot

Enter your passphrase when prompted.

This creates: /dev/mapper/cryptroot

Verify the mapper device exists:

    ls /dev/mapper/

You should see: cryptroot

### Save Your LUKS UUID

**CRITICAL:** You need this UUID for the bootloader!

Get LUKS UUID:

    blkid /dev/nvme0n1p2 -o value -s UUID

Example output: a1b2c3d4-e5f6-7890-abcd-ef1234567890

**WRITE THIS DOWN!** You'll need it later for bootloader configuration.

Alternative command to see full information:

    blkid /dev/nvme0n1p2

Look for the UUID value in the output.

---

## Btrfs Filesystem Creation

### Format with Btrfs

Create btrfs filesystem on encrypted partition:

    mkfs.btrfs /dev/mapper/cryptroot

Optional: Add a label to your filesystem:

    mkfs.btrfs -L "ArchLinux" /dev/mapper/cryptroot

Verify filesystem creation:

    btrfs filesystem show

You should see your new btrfs filesystem listed.

### Mount the Filesystem (Temporarily)

Mount to create subvolumes:

    mount /dev/mapper/cryptroot /mnt

---

## Subvolume Structure

### Understanding Subvolumes

We will create 5 subvolumes:

SUBVOLUME | PURPOSE | WHY SEPARATE?
----------|---------|---------------
@ | Root (/) | Main system files
@home | /home | User data, can snapshot separately
@var | /var | Logs, caches - often excluded from snapshots
@tmp | /tmp | Temporary files - never snapshot
@snapshots | /.snapshots | Store system snapshots

### Create Subvolumes

Navigate to mount point:

    cd /mnt

Create root subvolume:

    btrfs subvolume create @

Create home subvolume:

    btrfs subvolume create @home

Create var subvolume:

    btrfs subvolume create @var

Create tmp subvolume:

    btrfs subvolume create @tmp

Create snapshots subvolume:

    btrfs subvolume create @snapshots

List all subvolumes:

    btrfs subvolume list /mnt

Expected output:

    ID XXX gen XXX top level 5 path @
    ID XXX gen XXX top level 5 path @home
    ID XXX gen XXX top level 5 path @var
    ID XXX gen XXX top level 5 path @tmp
    ID XXX gen XXX top level 5 path @snapshots

### Unmount to Remount with Subvolumes

Unmount the filesystem:

    cd
    umount /mnt

### Mount Subvolumes with Options

**Btrfs mount options explained:**

OPTION | PURPOSE
-------|--------
compress=zstd:3 | Compression level 3 (good balance)
noatime | Don't update access time (faster, less writes)
space_cache=v2 | Better free space tracking
discard=async | Async TRIM for SSD (better performance)

Mount root subvolume (@):

    mount -o compress=zstd:3,noatime,space_cache=v2,discard=async,subvol=@ /dev/mapper/cryptroot /mnt

Create mount point directories:

    mkdir -p /mnt/{home,var,tmp,.snapshots}

Mount home subvolume (@home):

    mount -o compress=zstd:3,noatime,space_cache=v2,discard=async,subvol=@home /dev/mapper/cryptroot /mnt/home

Mount var subvolume (@var):

    mount -o compress=zstd:3,noatime,space_cache=v2,discard=async,subvol=@var /dev/mapper/cryptroot /mnt/var

Mount tmp subvolume (@tmp):

    mount -o compress=zstd:3,noatime,space_cache=v2,discard=async,subvol=@tmp /dev/mapper/cryptroot /mnt/tmp

Mount snapshots subvolume (@snapshots):

    mount -o compress=zstd:3,noatime,space_cache=v2,discard=async,subvol=@snapshots /dev/mapper/cryptroot /mnt/.snapshots

### Mount ESP Partition

Create boot directory:

    mkdir -p /mnt/boot

Format ESP partition:

    mkfs.fat -F32 /dev/nvme0n1p1

Mount ESP:

    mount /dev/nvme0n1p1 /mnt/boot

### Verify All Mounts

Check mount structure:

    lsblk

Expected output:

    NAME              SIZE TYPE  MOUNTPOINT
    nvme0n1           XXXG disk
    ├─nvme0n1p1       512M part  /mnt/boot
    └─nvme0n1p2       XXXG part
      └─cryptroot     XXXG crypt
        ├─/mnt              btrfs (subvol=@)
        ├─/mnt/home         btrfs (subvol=@home)
        ├─/mnt/var          btrfs (subvol=@var)
        ├─/mnt/tmp          btrfs (subvol=@tmp)
        └─/mnt/.snapshots   btrfs (subvol=@snapshots)

---

## Base System Installation

### Install Essential Packages

Install base system and essential packages:

    pacstrap -K /mnt base linux-hardened linux-firmware base-devel networkmanager nano vim man-db man-pages cryptsetup btrfs-progs intel-ucode

**Package breakdown:**
- base: Core Arch Linux system
- linux-hardened: Hardened kernel
- linux-firmware: Hardware drivers
- base-devel: Build tools (for AUR later)
- networkmanager: Network management
- nano, vim: Text editors
- man-db, man-pages: Manual pages
- cryptsetup: LUKS tools
- btrfs-progs: Btrfs utilities (CRITICAL for btrfs!)
- intel-ucode: Intel CPU microcode (use amd-ucode for AMD)

**Note:** Replace intel-ucode with amd-ucode if you have AMD CPU.

This will take 5-15 minutes depending on internet speed.

### Generate fstab

Generate fstab with UUIDs:

    genfstab -U /mnt >> /mnt/etc/fstab

**IMPORTANT:** Verify fstab was created correctly:

    cat /mnt/etc/fstab

Expected entries:
- Root (/) with subvol=@
- /home with subvol=@home
- /var with subvol=@var
- /tmp with subvol=@tmp
- /.snapshots with subvol=@snapshots
- /boot (ESP partition)

All btrfs entries should have compress=zstd:3 and other mount options.

---

## System Configuration

### Chroot into New System

Change root into your new system:

    arch-chroot /mnt

You are now inside your new Arch installation!

### Set Timezone

Set your timezone (example: Vienna):

    ln -sf /usr/share/zoneinfo/Europe/Vienna /etc/localtime

Find your timezone:

    ls /usr/share/zoneinfo/

Then navigate through regions/cities.

Sync hardware clock:

    hwclock --systohc

### Localization

Edit locale.gen:

    nano /etc/locale.gen

Uncomment your locale (example: en_US.UTF-8):

Find this line:

    #en_US.UTF-8 UTF-8

Remove the # to uncomment it:

    en_US.UTF-8 UTF-8

Save and exit: Ctrl+X, then Y, then Enter

Generate locales:

    locale-gen

Set system locale:

    echo "LANG=en_US.UTF-8" > /etc/locale.conf

### Network Configuration

Set hostname:

    echo "yourhostname" > /etc/hostname

Replace "yourhostname" with your preferred name (example: "arch-laptop" or "forge")

Edit hosts file:

    nano /etc/hosts

Add these lines:

    127.0.0.1   localhost
    ::1         localhost
    127.0.1.1   yourhostname.localdomain yourhostname

Replace "yourhostname" with the same name you used above.

Save and exit: Ctrl+X, then Y, then Enter

Enable NetworkManager:

    systemctl enable NetworkManager

### Set Root Password

**IMPORTANT:** Set a strong root password:

    passwd

Enter your password twice.

### Create User Account

Create your user account:

    useradd -m -G wheel -s /bin/bash yourusername

Replace "yourusername" with your desired username.

Set password for your user:

    passwd yourusername

Enter password twice.

### Configure sudo

Allow wheel group to use sudo:

    EDITOR=nano visudo

Find this line:

    # %wheel ALL=(ALL:ALL) ALL

Remove the # to uncomment it:

    %wheel ALL=(ALL:ALL) ALL

Save and exit: Ctrl+X, then Y, then Enter

---

## Initramfs Configuration

**CRITICAL SECTION:** This determines if your system boots!

### Edit mkinitcpio.conf

Open configuration file:

    nano /etc/mkinitcpio.conf

### Add Btrfs Module

Find the MODULES line:

    MODULES=()

Change it to:

    MODULES=(btrfs)

**CRITICAL:** Btrfs must be in MODULES array!

### Configure HOOKS

Find the HOOKS line (will look something like this):

    HOOKS=(base udev autodetect modconf block filesystems keyboard fsck)

**Replace it with:**

    HOOKS=(base systemd autodetect microcode modconf kms keyboard sd-vconsole block sd-encrypt filesystems fsck)

**HOOKS explained:**

HOOK | PURPOSE | POSITION MATTERS
-----|---------|------------------
base | Core functionality | Always first
systemd | systemd-based initramfs | Must be before sd-encrypt
autodetect | Auto-detect hardware | Early
microcode | CPU microcode loading | Early
modconf | Module configuration | Early
kms | Kernel mode setting | Before filesystem
keyboard | Keyboard support | BEFORE sd-encrypt!
sd-vconsole | Console settings | BEFORE sd-encrypt!
block | Block device support | Before encryption
sd-encrypt | systemd LUKS unlock | Before filesystems
filesystems | Filesystem support | After encryption
fsck | Filesystem check | Last

**Critical points:**
- Use systemd NOT udev
- Use sd-encrypt NOT encrypt
- keyboard and sd-vconsole MUST come before sd-encrypt
- Order matters!

### Generate Initramfs

Generate initramfs for all presets:

    mkinitcpio -P

This generates:
- initramfs-linux-hardened.img
- initramfs-linux-hardened-fallback.img

Verify files were created:

    ls -lh /boot/initramfs-*

You should see two files with recent timestamps.

---

## Bootloader Configuration

**CRITICAL SECTION:** This makes your system bootable!

### Install systemd-boot

Install bootloader to ESP:

    bootctl install

### Get Your LUKS UUID

**CRITICAL:** You need the UUID from your LUKS partition!

Get LUKS UUID:

    blkid /dev/nvme0n1p2 -o value -s UUID

**WRITE THIS DOWN!** Example: a1b2c3d4-e5f6-7890-abcd-ef1234567890

This is the UUID of /dev/nvme0n1p2 (encrypted partition), NOT the btrfs filesystem!

### Create Bootloader Entry

Create boot entry file:

    nano /boot/loader/entries/arch-hardened.conf

Add this content (REPLACE YOUR-LUKS-UUID with actual UUID!):

    title   Arch Linux Hardened
    linux   /vmlinuz-linux-hardened
    initrd  /intel-ucode.img
    initrd  /initramfs-linux-hardened.img
    options rd.luks.name=YOUR-LUKS-UUID=cryptroot root=/dev/mapper/cryptroot rootflags=subvol=@ rw

**CRITICAL PARAMETERS EXPLAINED:**

rd.luks.name=YOUR-LUKS-UUID=cryptroot
- YOUR-LUKS-UUID: UUID from blkid /dev/nvme0n1p2
- cryptroot: Name of the mapped device

root=/dev/mapper/cryptroot
- Points to unlocked LUKS device

rootflags=subvol=@
- Tells kernel to mount @ subvolume as root
- **CRITICAL FOR BTRFS!**

**Example with actual UUID:**

    title   Arch Linux Hardened
    linux   /vmlinuz-linux-hardened
    initrd  /intel-ucode.img
    initrd  /initramfs-linux-hardened.img
    options rd.luks.name=a1b2c3d4-e5f6-7890-abcd-ef1234567890=cryptroot root=/dev/mapper/cryptroot rootflags=subvol=@ rw

Save and exit: Ctrl+X, then Y, then Enter

### Configure Bootloader Defaults

Edit loader configuration:

    nano /boot/loader/loader.conf

Add this content:

    default arch-hardened.conf
    timeout 3
    console-mode max
    editor no

**Settings explained:**
- default: Boot entry to use
- timeout: Seconds to wait before auto-boot
- console-mode max: Best resolution
- editor no: Prevent editing boot parameters (security)

Save and exit: Ctrl+X, then Y, then Enter

### Add Hardened Kernel Parameters (Optional)

For additional security, edit boot entry again:

    nano /boot/loader/entries/arch-hardened.conf

Expand the options line to include hardening parameters:

    options rd.luks.name=YOUR-LUKS-UUID=cryptroot root=/dev/mapper/cryptroot rootflags=subvol=@ rw lockdown=confidentiality module.sig_enforce=1 slab_nomerge init_on_alloc=1 init_on_free=1 page_alloc.shuffle=1 randomize_kstack_offset=on vsyscall=none debugfs=off

**Hardening parameters explained:**

PARAMETER | PURPOSE
----------|--------
lockdown=confidentiality | Restrict kernel features
module.sig_enforce=1 | Only load signed modules
slab_nomerge | Prevent heap exploits
init_on_alloc=1 | Zero memory on allocation
init_on_free=1 | Zero memory on free
page_alloc.shuffle=1 | Randomize page allocator
randomize_kstack_offset=on | Randomize kernel stack
vsyscall=none | Disable legacy vsyscall
debugfs=off | Disable debug filesystem

Save and exit: Ctrl+X, then Y, then Enter

---

## Btrfs Maintenance

### Understanding Btrfs Maintenance

Btrfs requires periodic maintenance for optimal performance:

**Balance:** Rebalances data across the filesystem
**Scrub:** Verifies data integrity using checksums
**Defrag:** Reduces fragmentation (use carefully with CoW)

### Create Snapshot Script

Create directory for scripts:

    mkdir -p /usr/local/bin

Create snapshot script:

    nano /usr/local/bin/btrfs-snapshot

Add this content:

    #!/bin/bash
    # Create snapshot of root subvolume
    
    SNAPSHOT_DIR="/.snapshots"
    DATE=$(date +%Y-%m-%d_%H-%M-%S)
    
    btrfs subvolume snapshot / ${SNAPSHOT_DIR}/@_${DATE}
    
    echo "Snapshot created: @_${DATE}"
    
    # Keep only last 10 snapshots
    ls -1dt ${SNAPSHOT_DIR}/@_* | tail -n +11 | xargs -r btrfs subvolume delete

Make it executable:

    chmod +x /usr/local/bin/btrfs-snapshot

### Create Pacman Hook for Auto-Snapshots

Create hooks directory:

    mkdir -p /etc/pacman.d/hooks

Create snapshot hook:

    nano /etc/pacman.d/hooks/00-pre-snapshot.hook

Add this content:

    [Trigger]
    Operation = Upgrade
    Operation = Install
    Operation = Remove
    Type = Package
    Target = *
    
    [Action]
    Description = Creating pre-transaction btrfs snapshot...
    When = PreTransaction
    Exec = /usr/local/bin/btrfs-snapshot

This automatically creates a snapshot before every package operation!

### Btrfs Scrub (Monthly Maintenance)

Create scrub service:

    nano /etc/systemd/system/btrfs-scrub@.service

Add this content:

    [Unit]
    Description=Btrfs scrub on %f
    
    [Service]
    Type=oneshot
    ExecStart=/usr/bin/btrfs scrub start -B %f

Create monthly timer:

    nano /etc/systemd/system/btrfs-scrub@.timer

Add this content:

    [Unit]
    Description=Monthly Btrfs scrub on %f
    
    [Timer]
    OnCalendar=monthly
    Persistent=true
    
    [Install]
    WantedBy=timers.target

Enable monthly scrub:

    systemctl enable btrfs-scrub@-.timer

### Btrfs Balance (Optional)

For SSDs, periodic balance helps performance:

Create balance script:

    nano /usr/local/bin/btrfs-balance

Add this content:

    #!/bin/bash
    # Balance btrfs filesystem
    
    btrfs balance start -dusage=50 -musage=50 /

Make executable:

    chmod +x /usr/local/bin/btrfs-balance

Run manually when needed (every few months):

    sudo /usr/local/bin/btrfs-balance

---

## ESP Security

### Understanding ESP Security

The ESP (EFI System Partition) at /boot must be unencrypted for UEFI firmware.

However, we can limit local access.

### Set Restrictive Permissions

**Note:** These are applied AFTER you reboot into your new system, not during installation.

Secure boot directory:

    chmod 700 /boot
    chown root:root /boot

Secure kernel and initramfs:

    chmod 600 /boot/vmlinuz-linux-hardened
    chmod 600 /boot/initramfs-linux-hardened.img
    chmod 600 /boot/initramfs-linux-hardened-fallback.img
    chmod 600 /boot/intel-ucode.img

Secure EFI directory:

    chmod -R 700 /boot/EFI

### Create Permission Script

Create security script:

    nano /usr/local/bin/secure-boot-permissions

Add this content:

    #!/bin/bash
    # Secure ESP permissions after kernel updates
    
    chmod 700 /boot
    chmod 600 /boot/vmlinuz-*
    chmod 600 /boot/initramfs-*
    chmod 600 /boot/*-ucode.img
    chmod -R 700 /boot/EFI
    
    echo "ESP permissions secured"

Make executable:

    chmod +x /usr/local/bin/secure-boot-permissions

### Create Pacman Hook

Create hook for automatic permission securing:

    nano /etc/pacman.d/hooks/99-secure-esp.hook

Add this content:

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

### ESP Security Limitations

**What these permissions protect against:**
- Accidental modification by non-root users
- Casual snooping on running system
- Some local privilege escalation attempts

**What they do NOT protect against:**
- Physical access attacks
- Booting from external media
- Sophisticated boot-time attacks
- UEFI/BIOS level attacks

**For maximum security, also implement:**
- UEFI Secure Boot with custom keys
- BIOS/UEFI password
- Full disk encryption (which you have!)
- Physical security

---

## Final Steps and First Boot

### Exit Chroot

Exit the chroot environment:

    exit

You're now back in the installation environment.

### Unmount All Filesystems

Unmount everything:

    umount -R /mnt

### Reboot

Remove installation media and reboot:

    reboot

**Remove the USB drive!**

### First Boot

You should see:
1. UEFI loads systemd-boot
2. Arch Linux Hardened entry
3. **Password prompt for LUKS**
4. Enter your encryption passphrase
5. System boots to login prompt

Login with your username and password.

### Post-Installation Tasks

After first successful boot:

Connect to WiFi:

    nmtui

Or for wired:

    Already connected automatically

Test internet:

    ping -c 3 archlinux.org

Update system:

    sudo pacman -Syu

### Install Additional Software

Install basic tools:

    sudo pacman -S firefox git htop

Install display server and i3:

    sudo pacman -S xorg-server xorg-xinit i3-wm i3status dmenu rofi alacritty

---

## Troubleshooting

### Boot Fails - No Password Prompt

**Cause:** Initramfs missing sd-encrypt hook or wrong HOOKS order

**Solution:**

Boot from installation media:

    cryptsetup open /dev/nvme0n1p2 cryptroot
    mount -o subvol=@ /dev/mapper/cryptroot /mnt
    mount /dev/nvme0n1p1 /mnt/boot
    arch-chroot /mnt

Edit mkinitcpio.conf:

    nano /etc/mkinitcpio.conf

Verify HOOKS line:

    HOOKS=(base systemd autodetect microcode modconf kms keyboard sd-vconsole block sd-encrypt filesystems fsck)

Verify MODULES line:

    MODULES=(btrfs)

Regenerate initramfs:

    mkinitcpio -P

Exit and reboot:

    exit
    umount -R /mnt
    reboot

### Boot Fails - "Waiting for device"

**Cause:** Wrong UUID in bootloader or missing rootflags

**Solution:**

Boot from installation media and chroot (see above).

Verify LUKS UUID:

    blkid /dev/nvme0n1p2

Edit boot entry:

    nano /boot/loader/entries/arch-hardened.conf

Verify options line has:
- Correct LUKS UUID from blkid
- rootflags=subvol=@

Example:

    options rd.luks.name=CORRECT-UUID=cryptroot root=/dev/mapper/cryptroot rootflags=subvol=@ rw

Exit and reboot:

    exit
    umount -R /mnt
    reboot

### Boot Fails - "Unknown filesystem type"

**Cause:** Btrfs module not loaded

**Solution:**

Boot from installation media and chroot (see above).

Verify btrfs in MODULES:

    nano /etc/mkinitcpio.conf

Should have:

    MODULES=(btrfs)

Regenerate:

    mkinitcpio -P

Exit and reboot.

### Emergency Shell - Can't Mount Root

**Cause:** Missing rootflags=subvol=@ or wrong subvolume name

**Solution:**

In emergency shell, check subvolumes:

    mkdir /tmp/btrfs
    mount /dev/mapper/cryptroot /tmp/btrfs
    btrfs subvolume list /tmp/btrfs

Verify @ subvolume exists.

Boot from installation media, chroot, and fix bootloader entry.

### Btrfs Errors - "No space left"

**Cause:** Btrfs metadata full (not actual space)

**Solution:**

Run balance:

    sudo btrfs balance start -dusage=5 /

If that doesn't work:

    sudo btrfs balance start -musage=5 /

Check space usage:

    sudo btrfs filesystem usage /

### Snapshots Taking Too Much Space

**Cause:** Too many snapshots or large changes

**Solution:**

List snapshots:

    sudo btrfs subvolume list /.snapshots

Delete old snapshots:

    sudo btrfs subvolume delete /.snapshots/@_2024-XX-XX_XX-XX-XX

Or delete all old snapshots:

    sudo ls -1dt /.snapshots/@_* | tail -n +6 | xargs -r sudo btrfs subvolume delete

---

## Btrfs Commands Reference

### Common Btrfs Commands

**Check filesystem:**

    sudo btrfs filesystem show
    sudo btrfs filesystem usage /

**List subvolumes:**

    sudo btrfs subvolume list /

**Create snapshot:**

    sudo btrfs subvolume snapshot / /.snapshots/@_backup

**Delete snapshot:**

    sudo btrfs subvolume delete /.snapshots/@_backup

**Scrub filesystem:**

    sudo btrfs scrub start /
    sudo btrfs scrub status /

**Balance filesystem:**

    sudo btrfs balance start /
    sudo btrfs balance status /

**Defragment (use sparingly):**

    sudo btrfs filesystem defragment -r /

**Check compression ratio:**

    sudo compsize /

Install compsize:

    sudo pacman -S compsize

---

## Verification Checklist

Before rebooting, verify:

- LUKS partition created on /dev/nvme0n1p2
- ESP formatted as FAT32 on /dev/nvme0n1p1
- Btrfs filesystem created on /dev/mapper/cryptroot
- All 5 subvolumes created (@, @home, @var, @tmp, @snapshots)
- All subvolumes mounted with correct options
- Filesystems mounted during installation
- LUKS UUID saved and used in boot entry
- btrfs in MODULES array
- initramfs HOOKS include: systemd, keyboard, sd-vconsole, sd-encrypt
- Boot entry includes rootflags=subvol=@
- initramfs generated successfully
- Bootloader installed with bootctl
- NetworkManager enabled
- Root password set
- User account created

---

## Quick Reference Card

### Critical UUIDs

Get LUKS UUID (for bootloader):

    blkid /dev/nvme0n1p2 -o value -s UUID

Get filesystem UUID (automatic in fstab):

    blkid /dev/mapper/cryptroot -o value -s UUID

### Boot Entry Format

    title   Arch Linux Hardened
    linux   /vmlinuz-linux-hardened
    initrd  /intel-ucode.img
    initrd  /initramfs-linux-hardened.img
    options rd.luks.name=LUKS-UUID=cryptroot root=/dev/mapper/cryptroot rootflags=subvol=@ rw

### mkinitcpio Configuration

    MODULES=(btrfs)
    
    HOOKS=(base systemd autodetect microcode modconf kms keyboard sd-vconsole block sd-encrypt filesystems fsck)

### Mount Options for Btrfs

    compress=zstd:3,noatime,space_cache=v2,discard=async,subvol=SUBVOLUME

### Common Recovery Commands

Unlock LUKS:

    cryptsetup open /dev/nvme0n1p2 cryptroot

Mount for recovery:

    mount -o subvol=@ /dev/mapper/cryptroot /mnt
    mount -o subvol=@home /dev/mapper/cryptroot /mnt/home
    mount -o subvol=@var /dev/mapper/cryptroot /mnt/var
    mount -o subvol=@tmp /dev/mapper/cryptroot /mnt/tmp
    mount -o subvol=@snapshots /dev/mapper/cryptroot /mnt/.snapshots
    mount /dev/nvme0n1p1 /mnt/boot

Chroot:

    arch-chroot /mnt

Regenerate initramfs:

    mkinitcpio -P

Update bootloader:

    bootctl update

---

## Additional Resources

- Arch Wiki LUKS: https://wiki.archlinux.org/title/Dm-crypt
- Arch Wiki Btrfs: https://wiki.archlinux.org/title/Btrfs
- Arch Wiki Installation: https://wiki.archlinux.org/title/Installation_guide
- Arch Wiki systemd-boot: https://wiki.archlinux.org/title/Systemd-boot
- Arch Wiki Snapper: https://wiki.archlinux.org/title/Snapper

---

## Package List for Complete System

After successful installation, install these packages:

**System utilities:**

    sudo pacman -S htop neofetch man-db man-pages wget curl

**Development tools:**

    sudo pacman -S git vim neovim base-devel

**Display server and window manager:**

    sudo pacman -S xorg-server xorg-xinit i3-wm i3status i3lock dmenu rofi

**Terminal and shell:**

    sudo pacman -S alacritty zsh

**Applications:**

    sudo pacman -S firefox thunar

**Fonts:**

    sudo pacman -S terminus-font ttf-dejavu ttf-liberation

**Audio:**

    sudo pacman -S pulseaudio pavucontrol

**Other utilities:**

    sudo pacman -S scrot feh picom brightnessctl

---

**Document End**

**Remember:**
- Your LUKS passphrase is required on every boot
- Create regular snapshots before system updates
- Run btrfs scrub monthly for data integrity
- Balance btrfs filesystem periodically for performance
- Keep your system updated with: sudo pacman -Syu

**Good luck with your installation!**

---

**Document Version:** 2.0 - Btrfs Edition  
**Last Updated:** November 2025  
**For:** Encrypted Arch Linux with Btrfs and systemd