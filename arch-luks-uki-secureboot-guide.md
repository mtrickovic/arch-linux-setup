# Arch Linux — UKI + Secure Boot with sbctl
## Unified Kernel Image & Secure Boot on Top of an Existing Installation

**Target Configuration:**
- linux-hardened kernel
- LUKS encrypted root (ext4 or btrfs — both supported)
- Unified Kernel Image (UKI) — kernel + initramfs + cmdline in one signed EFI binary
- sbctl for Secure Boot key management
- systemd-boot bootloader
- Secure Boot in User Mode (custom keys, no Microsoft CA required — optional)

**Document Version:** 1.0  
**Last Updated:** April 2026

---

## Table of Contents

1. [What is a UKI and Why Use It?](#what-is-a-uki-and-why-use-it)
2. [Prerequisites](#prerequisites)
3. [Install Required Packages](#install-required-packages)
4. [Configure Kernel Command Line](#configure-kernel-command-line)
5. [Configure mkinitcpio for UKI Output](#configure-mkinitcpio-for-uki-output)
6. [Build the UKI](#build-the-uki)
7. [Configure systemd-boot for UKI](#configure-systemd-boot-for-uki)
8. [Enter UEFI Setup Mode](#enter-uefi-setup-mode)
9. [Create and Enroll Secure Boot Keys](#create-and-enroll-secure-boot-keys)
10. [Sign the UKI](#sign-the-uki)
11. [Automate Signing with Pacman Hooks](#automate-signing-with-pacman-hooks)
12. [Reboot and Verify](#reboot-and-verify)
13. [Key Management and Backup](#key-management-and-backup)
14. [Troubleshooting](#troubleshooting)
15. [Quick Reference](#quick-reference)

---

## What is a UKI and Why Use It?

### Traditional Boot vs. UKI

**Traditional (what the other guides in this repo use):**

```
systemd-boot → reads arch-hardened.conf
             → loads vmlinuz-linux-hardened    (unsigned)
             → loads initramfs-linux-hardened.img  (unsigned)
             → reads kernel cmdline from .conf file  (unsigned)
```

Any of those three components can be tampered with without Secure Boot detecting it.

**UKI boot:**

```
systemd-boot → loads arch-linux-hardened.efi   (ONE signed binary)
             └─ contains: kernel + initramfs + cmdline (all baked in)
```

The entire boot chain is captured in a single EFI binary that is cryptographically signed.

### Why This Matters

| Threat | Traditional | UKI + Secure Boot |
|--------|------------|-------------------|
| Tampered kernel | ❌ Undetected | ✅ Signature check fails |
| Tampered initramfs | ❌ Undetected | ✅ Signature check fails |
| Malicious kernel parameter injected at boot | ❌ Possible | ✅ Cmdline is baked in and signed |
| Evil maid attack (boot files on ESP) | ❌ Vulnerable | ✅ Detected on next boot |

### What sbctl Does

`sbctl` (Secure Boot Control) is an Arch-friendly tool that:
- Generates your own Secure Boot Platform Key (PK), Key Exchange Key (KEK), and Database Key (db)
- Enrolls those keys into UEFI firmware
- Signs EFI binaries (your UKI, systemd-boot itself)
- Tracks which files need to be signed and re-signs them via pacman hooks

---

## Prerequisites

This guide **starts from a working Arch Linux installation** using one of:
- `arch-luks-install-guide.md` (ext4 setup)
- `arch-luks-btrfs-guide.md` (btrfs setup)

Before continuing, make sure:
- [ ] System boots successfully with LUKS decryption
- [ ] You are booted into the installed system (not the live ISO)
- [ ] `systemd-boot` is installed and working (`bootctl status`)
- [ ] Internet connection is active
- [ ] You know your LUKS UUID (`blkid /dev/sda2 -o value -s UUID` or `blkid /dev/nvme0n1p2 ...`)
- [ ] UEFI Secure Boot is currently **disabled** in firmware (you will enable it later)

Check current Secure Boot status:
```bash
sbctl status
# or
bootctl | grep -i "secure boot"
```

---

## Install Required Packages

```bash
sudo pacman -S sbctl
```

`sbctl` pulls in `efitools` as a dependency. That is everything you need — UKI generation is handled by `mkinitcpio` (already installed).

Optionally install `efibootmgr` for inspecting/editing UEFI boot entries:
```bash
sudo pacman -S efibootmgr
```

---

## Configure Kernel Command Line

With UKI, the kernel cmdline is **baked into the EFI binary at build time** — it is no longer read from the bootloader `.conf` file at runtime. This is what makes it tamper-proof when signed.

### Create the cmdline file

```bash
sudo nano /etc/kernel/cmdline
```

**For ext4 installations:**
```
rd.luks.name=YOUR-LUKS-UUID=cryptroot root=/dev/mapper/cryptroot rw lockdown=confidentiality module.sig_enforce=1 slab_nomerge init_on_alloc=1 init_on_free=1 page_alloc.shuffle=1 randomize_kstack_offset=on vsyscall=none debugfs=off
```

**For btrfs installations (add `rootflags`):**
```
rd.luks.name=YOUR-LUKS-UUID=cryptroot root=/dev/mapper/cryptroot rootflags=subvol=@ rw lockdown=confidentiality module.sig_enforce=1 slab_nomerge init_on_alloc=1 init_on_free=1 page_alloc.shuffle=1 randomize_kstack_offset=on vsyscall=none debugfs=off
```

**Replace `YOUR-LUKS-UUID` with your actual LUKS partition UUID:**
```bash
# ext4 (sda disk)
blkid /dev/sda2 -o value -s UUID

# btrfs (nvme disk)
blkid /dev/nvme0n1p2 -o value -s UUID
```

**Important:** This file must be a **single line** with no newline at the end. Verify:
```bash
cat /etc/kernel/cmdline
wc -l /etc/kernel/cmdline   # Should print: 1
```

---

## Configure mkinitcpio for UKI Output

### Verify mkinitcpio HOOKS (same as before)

```bash
cat /etc/mkinitcpio.conf | grep ^HOOKS
```

Expected output (should already be set from the base installation):
```
HOOKS=(base systemd autodetect microcode modconf kms keyboard sd-vconsole block sd-encrypt filesystems fsck)
```

For btrfs, also verify:
```
MODULES=(btrfs)
```

### Edit the linux-hardened preset

This is the key step. Instead of generating a separate `vmlinuz` + `initramfs`, we tell mkinitcpio to produce a single `.efi` UKI file.

```bash
sudo nano /etc/mkinitcpio.d/linux-hardened.preset
```

Replace the entire file content with:

```bash
# mkinitcpio preset for linux-hardened — UKI mode

ALL_config="/etc/mkinitcpio.conf"
ALL_kver="/boot/vmlinuz-linux-hardened"
ALL_microcode=(/boot/*-ucode.img)

PRESETS=('default' 'fallback')

# UKI output paths — these become signed EFI binaries
default_uki="/boot/EFI/Linux/arch-linux-hardened.efi"
default_options="--splash /usr/share/systemd/bootctl/splash-arch.bmp"

fallback_uki="/boot/EFI/Linux/arch-linux-hardened-fallback.efi"
fallback_options="-S autodetect"
```

**What changed:**
- `default_image` (initramfs path) is replaced by `default_uki` (EFI binary path)
- `ALL_microcode` bundles your CPU microcode directly into the UKI
- The splash line is optional but adds the Arch logo at boot

### Create the output directory

```bash
sudo mkdir -p /boot/EFI/Linux
```

---

## Build the UKI

```bash
sudo mkinitcpio -P
```

Verify the output:
```bash
ls -lh /boot/EFI/Linux/
# Should show:
# arch-linux-hardened.efi          (main UKI, typically 40–80 MB)
# arch-linux-hardened-fallback.efi (fallback without autodetect)
```

**Note:** You will no longer see separate `initramfs-linux-hardened.img` files being used for booting. The old `.img` files may still exist on disk but are not referenced by the new UKI preset.

---

## Configure systemd-boot for UKI

systemd-boot can auto-discover UKIs placed in `/boot/EFI/Linux/` that follow the naming convention — no manual `.conf` entry needed. However, creating an explicit entry gives you control over the title and boot order.

### Option A — Auto-discovery (simplest)

systemd-boot automatically picks up any `.efi` file in `/boot/EFI/Linux/` that was built with a valid UKI structure (it reads the embedded OS release). No configuration needed beyond updating `loader.conf`.

```bash
sudo nano /boot/loader/loader.conf
```

```
timeout 3
console-mode max
editor no
```

Verify it will be discovered:
```bash
bootctl list
# Should show your arch-linux-hardened.efi entry
```

### Option B — Explicit entry (recommended for clarity)

```bash
sudo nano /boot/loader/entries/arch-hardened-uki.conf
```

```
title   Arch Linux Hardened (UKI)
efi     /EFI/Linux/arch-linux-hardened.efi
```

**Notice:** No `linux`, `initrd`, or `options` lines — those are all embedded inside the UKI itself.

Remove or rename the old non-UKI entry if it exists:
```bash
sudo mv /boot/loader/entries/arch-hardened.conf \
        /boot/loader/entries/arch-hardened.conf.bak
```

---

## Enter UEFI Setup Mode

For sbctl to enroll your keys, the firmware must be in **Setup Mode**. This clears the existing Secure Boot key database.

> **Warning:** Clearing Secure Boot keys means that until you enroll your own keys and enable Secure Boot, the system will boot without signature verification. Complete this section in one sitting.

### Steps (varies by firmware vendor)

1. **Reboot** into UEFI/BIOS settings
   - Common keys: `Del`, `F2`, `F10`, `Escape` during POST
2. Navigate to the **Security** or **Boot** section
3. Find **Secure Boot** settings
4. Look for **"Clear Secure Boot keys"**, **"Reset to Setup Mode"**, or **"Delete all Secure Boot variables"**
5. Confirm and **save & exit** — boot back into Arch Linux

### Verify Setup Mode is active

```bash
sbctl status
```

Expected output:
```
Installed:    ✓ sbctl is installed
Owner GUID:   xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
Setup Mode:   ✓ Enabled
Secure Boot:  ✗ Disabled
Vendor Keys:  none
```

Both "Setup Mode: Enabled" and "Secure Boot: Disabled" must show before proceeding.

---

## Create and Enroll Secure Boot Keys

### Generate your keys

```bash
sudo sbctl create-keys
```

This creates three key pairs under `/usr/share/secureboot/keys/`:
- `PK` — Platform Key (root of trust, signs KEK)
- `KEK` — Key Exchange Key (signs db updates)
- `db` — Signature Database Key (signs EFI binaries)

### Enroll your keys

**Option A — Custom keys only (maximum control, no Microsoft CA):**
```bash
sudo sbctl enroll-keys
```

Use this if you control all EFI binaries that boot on this machine and do not need to boot Windows or vendor-signed option ROMs.

**Option B — Custom keys + Microsoft keys (broader compatibility):**
```bash
sudo sbctl enroll-keys -m
```

Use this if you also need to boot Windows, or if your hardware has UEFI option ROMs (e.g., GPU firmware, Thunderbolt) that require Microsoft signing.

**Recommended for most laptops:** Option B (`-m`), since peripheral firmware is often Microsoft-signed.

### Verify enrollment

```bash
sbctl status
```

Expected output after enrollment:
```
Installed:    ✓ sbctl is installed
Owner GUID:   xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
Setup Mode:   ✗ Disabled     ← Setup Mode is now locked
Secure Boot:  ✗ Disabled     ← Still disabled until you enable in firmware
Vendor Keys:  microsoft      ← (if you used -m)
```

---

## Sign the UKI

### Sign all required EFI binaries

sbctl needs to sign:
1. The systemd-boot EFI binary itself
2. Your UKI(s)

```bash
# Sign systemd-boot
sudo sbctl sign -s /boot/EFI/systemd/systemd-bootx64.efi
sudo sbctl sign -s /boot/EFI/BOOT/BOOTX64.EFI

# Sign your UKIs
sudo sbctl sign -s /boot/EFI/Linux/arch-linux-hardened.efi
sudo sbctl sign -s /boot/EFI/Linux/arch-linux-hardened-fallback.efi
```

The `-s` flag **saves the path to sbctl's database** so it can automatically re-sign these files after kernel updates.

### Verify all signatures

```bash
sudo sbctl verify
```

Expected output:
```
Verifying file database and EFI images in /boot...
✓ /boot/EFI/BOOT/BOOTX64.EFI is signed
✓ /boot/EFI/Linux/arch-linux-hardened.efi is signed
✓ /boot/EFI/Linux/arch-linux-hardened-fallback.efi is signed
✓ /boot/EFI/systemd/systemd-bootx64.efi is signed
```

Every binary must show ✓ before you enable Secure Boot.

---

## Automate Signing with Pacman Hooks

Every time `linux-hardened` or `systemd-boot` is updated, the EFI binaries change and must be re-signed. sbctl handles this automatically via a pacman hook.

### Check that sbctl's hook is active

sbctl installs its own pacman hook at `/usr/share/libalpm/hooks/zz-sbctl.hook`. Verify it exists:

```bash
cat /usr/share/libalpm/hooks/zz-sbctl.hook
```

This hook runs `sbctl sign-all` after every transaction that touches files in sbctl's sign database. Since we used `-s` when signing, all four paths are tracked.

### Test the automation

Simulate a kernel update to confirm re-signing works:
```bash
sudo mkinitcpio -P        # rebuilds UKIs
sudo sbctl verify         # all should still be signed (hook ran)
```

If you ever add a new EFI binary (e.g., after installing a second kernel), sign and track it:
```bash
sudo sbctl sign -s /boot/EFI/Linux/new-binary.efi
```

---

## Reboot and Verify

### Enable Secure Boot in firmware

1. Reboot into UEFI/BIOS settings
2. Navigate to **Security → Secure Boot**
3. Set Secure Boot to **Enabled**
4. Save and exit — the system will boot

### Verify Secure Boot is active

After booting into Arch Linux:

```bash
sbctl status
```

Expected final output:
```
Installed:    ✓ sbctl is installed
Owner GUID:   xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
Setup Mode:   ✗ Disabled
Secure Boot:  ✓ Enabled
Vendor Keys:  microsoft
```

Also verify via kernel:
```bash
cat /sys/firmware/efi/efivars/SecureBoot-*  | xxd | tail -1
# Last byte should be 01 (enabled)
```

Or simply:
```bash
bootctl | grep "Secure Boot"
# Secure Boot: enabled (user)
```

The `(user)` confirms you are in User Mode with your own custom keys — not in the insecure "deployed" mode with only vendor keys.

---

## Key Management and Backup

### Back up your Secure Boot keys

Your private keys are the root of trust. If lost, you cannot sign new binaries without re-entering Setup Mode and starting over.

```bash
sudo cp -r /usr/share/secureboot/keys /path/to/secure/backup/
```

Store this backup on an **encrypted, offline drive** (e.g., a LUKS-encrypted USB).

### Key locations

| Key | Private key | Certificate |
|-----|-------------|-------------|
| PK  | `/usr/share/secureboot/keys/PK/PK.key` | `PK.pem` |
| KEK | `/usr/share/secureboot/keys/KEK/KEK.key` | `KEK.pem` |
| db  | `/usr/share/secureboot/keys/db/db.key` | `db.pem` |

### Inspect signed files

```bash
sudo sbctl list-files
```

### Remove a file from tracking

```bash
sudo sbctl remove-file /path/to/binary.efi
```

---

## Troubleshooting

### Secure Boot blocks boot — "Security Violation"

**Cause:** A binary is unsigned or the signature does not match enrolled keys.

**Solution:**
1. Temporarily disable Secure Boot in firmware
2. Boot into Arch Linux
3. Run `sudo sbctl verify` — identify the unsigned file
4. Sign it: `sudo sbctl sign -s /path/to/unsigned.efi`
5. Re-enable Secure Boot

### UKI not found — systemd-boot shows no entries

**Cause:** UKI not built yet, wrong path, or auto-discovery not recognizing the file.

**Solution:**
```bash
# Verify UKI exists
ls -lh /boot/EFI/Linux/

# Rebuild if missing
sudo mkinitcpio -P

# Check bootctl discovery
bootctl list
```

Also verify `/boot/EFI/Linux/` exists and is on the ESP (FAT32 partition mounted at `/boot`).

### "Setup Mode: Disabled" but keys not enrolled

**Cause:** Firmware exited Setup Mode when you saved, but sbctl enrollment failed.

**Solution:**
1. Re-enter firmware settings
2. Clear/reset Secure Boot keys again to re-enter Setup Mode
3. Boot into Arch and retry `sudo sbctl enroll-keys`

### Password prompt missing — LUKS not unlocking

**Cause:** Kernel cmdline in `/etc/kernel/cmdline` has wrong UUID, or `sd-encrypt` hook is missing.

**Solution:**
```bash
# Verify cmdline
cat /etc/kernel/cmdline

# Verify UUID matches your LUKS partition
blkid /dev/sda2        # ext4 setup
blkid /dev/nvme0n1p2   # btrfs/nvme setup

# Fix if wrong, then rebuild UKI
sudo mkinitcpio -P
sudo sbctl sign -s /boot/EFI/Linux/arch-linux-hardened.efi
sudo sbctl sign -s /boot/EFI/Linux/arch-linux-hardened-fallback.efi
```

**Remember:** After changing `/etc/kernel/cmdline`, you **must** rebuild the UKI and re-sign it — the old signed binary still has the old cmdline baked in.

### Module signature enforcement blocks drivers

**Cause:** `module.sig_enforce=1` in cmdline rejects unsigned kernel modules (e.g., proprietary NVIDIA, VirtualBox guest additions).

**Solution — option A:** Remove `module.sig_enforce=1` from `/etc/kernel/cmdline`, rebuild UKI, re-sign.

**Solution — option B:** Use DKMS modules that are signed by linux-hardened's own key (Arch packages handle this for most modules in the official repos).

### After kernel update — Secure Boot blocks boot

**Cause:** Pacman hook did not re-sign the new UKI (or hook ran before UKI was built).

**Solution:**
```bash
# Rebuild and re-sign manually
sudo mkinitcpio -P
sudo sbctl sign-all
sudo sbctl verify
```

---

## Quick Reference

### Build and sign flow

```bash
# 1. Edit kernel cmdline
sudo nano /etc/kernel/cmdline

# 2. Rebuild UKI
sudo mkinitcpio -P

# 3. Sign everything
sudo sbctl sign-all

# 4. Verify
sudo sbctl verify
```

### Key sbctl commands

```bash
# Status overview
sbctl status

# Create keys (once only)
sudo sbctl create-keys

# Enroll keys into firmware
sudo sbctl enroll-keys -m

# Sign a binary and track it
sudo sbctl sign -s /path/to/binary.efi

# Re-sign all tracked files
sudo sbctl sign-all

# Verify all tracked files are signed
sudo sbctl verify

# List all tracked files
sudo sbctl list-files
```

### Recovery from live ISO

```bash
# Unlock LUKS
cryptsetup open /dev/sda2 cryptroot       # ext4
# or
cryptsetup open /dev/nvme0n1p2 cryptroot  # btrfs

# Mount — ext4
mount /dev/mapper/cryptroot /mnt
mount /dev/sda1 /mnt/boot

# Mount — btrfs
mount -o subvol=@ /dev/mapper/cryptroot /mnt
mount /dev/nvme0n1p1 /mnt/boot

# Chroot
arch-chroot /mnt

# Rebuild UKI
mkinitcpio -P

# Re-sign (sbctl keys are on the encrypted root, so available after chroot)
sbctl sign-all
sbctl verify
```

### File locations summary

| File | Purpose |
|------|---------|
| `/etc/kernel/cmdline` | Kernel parameters baked into UKI |
| `/etc/mkinitcpio.d/linux-hardened.preset` | UKI output configuration |
| `/boot/EFI/Linux/arch-linux-hardened.efi` | Main UKI (signed EFI binary) |
| `/boot/EFI/Linux/arch-linux-hardened-fallback.efi` | Fallback UKI |
| `/usr/share/secureboot/keys/` | sbctl key storage |
| `/usr/share/libalpm/hooks/zz-sbctl.hook` | Automatic re-signing hook |

---

## Additional Resources

- Arch Wiki — Unified Kernel Image: https://wiki.archlinux.org/title/Unified_kernel_image
- Arch Wiki — Secure Boot: https://wiki.archlinux.org/title/Unified_Extensible_Firmware_Interface/Secure_Boot
- Arch Wiki — sbctl: https://wiki.archlinux.org/title/Sbctl
- sbctl GitHub: https://github.com/Foxboron/sbctl
- Arch Wiki — dm-crypt: https://wiki.archlinux.org/title/Dm-crypt

---

**Good luck, and boot with confidence!**
