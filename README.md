# arch-linux-setup

Personal collection of Arch Linux installation guides — hardened kernel, full-disk encryption, and Secure Boot using custom keys.

All guides target `linux-hardened`, `systemd-boot`, and a `systemd`-based initramfs. Pick the guide that matches your filesystem and security requirements.

---

## Guides

### 1. `arch-luks-install-guide.md` — LUKS + ext4

The straightforward starting point. Good performance, simple recovery, easy to understand.

**Stack:** linux-hardened · LUKS2 · ext4 · systemd-boot · sd-encrypt  
**Good for:** First-time encrypted Arch installs, VMs, hardware where you want simplicity

---

### 2. `arch-luks-btrfs-guide.md` — LUKS + btrfs

Adds btrfs on top of LUKS with a proper subvolume layout (`@`, `@home`, `@var`, `@tmp`, `@snapshots`), compression, and snapshotting support.

**Stack:** linux-hardened · LUKS2 · btrfs · systemd-boot · sd-encrypt  
**Good for:** Systems where you want rollback capability and efficient snapshots before upgrades

Key additions over the ext4 guide:
- zstd compression
- Subvolume layout compatible with Snapper / Timeshift
- btrfs maintenance (scrub, balance) instructions

---

### 3. `arch-luks-uki-secureboot-guide.md` — UKI + Secure Boot with sbctl

Builds on top of either of the above guides. Replaces the traditional `vmlinuz + initramfs + .conf` boot with a single signed EFI binary (Unified Kernel Image), and enables Secure Boot with your own custom keys managed by `sbctl`.

**Stack:** linux-hardened · LUKS2 · ext4 or btrfs · systemd-boot · UKI · sbctl  
**Good for:** Laptops and machines where you want a complete, verified boot chain

What this adds:
- Kernel cmdline baked into and signed inside the EFI binary
- Tamper detection for kernel, initramfs, and boot parameters
- Your own Platform Key — no dependency on Microsoft CA (optional)
- Automatic re-signing after kernel updates via pacman hook

---

## Recommended Path

```
New machine or VM?
│
├─ Want snapshots / rollback?
│   └─ Yes → arch-luks-btrfs-guide.md
│   └─ No  → arch-luks-install-guide.md
│
└─ Add Secure Boot after first successful boot?
    └─ Yes → arch-luks-uki-secureboot-guide.md
```

The UKI + Secure Boot guide is written as a **post-installation step** — get a working encrypted system first, then layer on the signed boot chain.

---

## Common Stack Across All Guides

| Component | Choice | Reason |
|-----------|--------|--------|
| Kernel | `linux-hardened` | Additional security patches and stricter defaults |
| Bootloader | `systemd-boot` | Simple, UEFI-native, no GRUB complexity |
| initramfs | `systemd` hooks | Required for `sd-encrypt`, consistent with UKI |
| LUKS unlock | `sd-encrypt` | systemd-native hook, works with UKI |
| Microcode | Bundled in initramfs / UKI | CPU vulnerability mitigations applied early |
| Network | `NetworkManager` | Works well for both wired and WiFi post-install |

---

## Hardened Kernel Parameters

All guides use the same set of hardening parameters on the kernel cmdline:

```
lockdown=confidentiality      # Restrict kernel features that leak data
module.sig_enforce=1          # Only load signed kernel modules
slab_nomerge                  # Prevent heap exploit techniques
init_on_alloc=1               # Zero memory on allocation
init_on_free=1                # Zero memory on free
page_alloc.shuffle=1          # Randomize page allocator freelists
randomize_kstack_offset=on    # Randomize kernel stack offset
vsyscall=none                 # Disable legacy vsyscall interface
debugfs=off                   # Disable debug filesystem
```

In the UKI guide these parameters are **signed** — they cannot be changed at boot without invalidating the signature.

---

## Security Model Summary

| Protection | ext4 guide | btrfs guide | UKI + Secure Boot |
|------------|:---------:|:-----------:|:-----------------:|
| Encrypted root | ✅ | ✅ | ✅ |
| Hardened kernel | ✅ | ✅ | ✅ |
| Hardened kernel params | ✅ | ✅ | ✅ + signed |
| Signed kernel | ❌ | ❌ | ✅ |
| Signed initramfs | ❌ | ❌ | ✅ |
| Signed cmdline | ❌ | ❌ | ✅ |
| Evil maid detection | ❌ | ❌ | ✅ |
| Snapshot / rollback | ❌ | ✅ | ✅ (with btrfs base) |

---

## Notes

- All guides use `/dev/sda` (ext4) or `/dev/nvme0n1` (btrfs) as example disk names — replace with your actual disk throughout.
- CPU microcode: guides default to `intel-ucode`. Replace with `amd-ucode` for AMD machines.
- Tested on real hardware and QEMU/KVM.
- These are personal reference guides, not a substitute for the [Arch Wiki](https://wiki.archlinux.org). When in doubt, the wiki wins.

---

## Resources

- [Arch Wiki — Installation Guide](https://wiki.archlinux.org/title/Installation_guide)
- [Arch Wiki — dm-crypt](https://wiki.archlinux.org/title/Dm-crypt)
- [Arch Wiki — Btrfs](https://wiki.archlinux.org/title/Btrfs)
- [Arch Wiki — systemd-boot](https://wiki.archlinux.org/title/Systemd-boot)
- [Arch Wiki — Unified Kernel Image](https://wiki.archlinux.org/title/Unified_kernel_image)
- [Arch Wiki — Secure Boot](https://wiki.archlinux.org/title/Unified_Extensible_Firmware_Interface/Secure_Boot)
- [sbctl on GitHub](https://github.com/Foxboron/sbctl)
