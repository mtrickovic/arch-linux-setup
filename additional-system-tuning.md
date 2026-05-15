# Additional System Tuning & Configuration

Post-install hardening and quality-of-life improvements for Arch Linux with LUKS + UKI + Secure Boot.

---

## 🔴 High Priority

### SSD Health — `fstrim.timer`

Sends TRIM commands to the SSD on a regular schedule, essential for long-term NVMe health.

```bash
sudo systemctl enable --now fstrim.timer
```

### Firewall — `ufw`

A default-deny firewall. No inbound connections allowed unless explicitly permitted.

```bash
sudo pacman -S ufw
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw enable
sudo systemctl enable ufw
```

### Data Backup — `restic`

Encrypts and deduplicates backups to local drives, SFTP, or cloud backends such
as Backblaze B2.

```bash
sudo pacman -S restic
```

Basic usage — initialize a repo and back up your home directory:

```bash
restic init --repo /path/to/backup/location
restic -r /path/to/backup/location backup /home/yourusername
```

---

## 🟡 Worth Adding

### Mirror Management — `reflector`

Keeps pacman mirrors sorted by speed and freshness automatically.

```bash
sudo pacman -S reflector
sudo systemctl enable reflector.timer
```

Optionally configure it at `/etc/xdg/reflector/reflector.conf`:

```
--country Sweden,Germany,Netherlands
--protocol https
--latest 10
--sort rate
--save /etc/pacman.d/mirrorlist
```

### Package Cache Cleanup — `paccache`

Pacman accumulates old package versions silently. This keeps only the last 3 versions
and runs automatically on a timer.

```bash
sudo pacman -S pacman-contrib
sudo systemctl enable --now paccache.timer
```

### Intel Thermal Management — `thermald`

Manages thermal throttling intelligently for Intel CPUs. Relevant for sustained workloads
on the i7-1165G7.

```bash
sudo pacman -S thermald
sudo systemctl enable --now thermald
```

### DNS over TLS — `systemd-resolved`

DNS traffic is plaintext by default. This enables encrypted DNS via Quad9 with DNSSEC
validation using the built-in systemd-resolved.

Edit `/etc/systemd/resolved.conf`:

```ini
[Resolve]
DNS=9.9.9.9#dns.quad9.net
DNSOverTLS=yes
DNSSEC=yes
```

Then restart the service:

```bash
sudo systemctl restart systemd-resolved
```

Verify it is working:

```bash
resolvectl status
```

---

## 🟢 Nice to Have

### OOM Prevention — `earlyoom`

Prevents the system from freezing under memory pressure by gracefully killing processes
before the kernel OOM killer kicks in.

```bash
sudo pacman -S earlyoom
sudo systemctl enable --now earlyoom
```

### CPU Frequency Scaling — `auto-cpufreq`

Intelligent CPU governor management for laptops. Better than the default for balancing
performance and battery life dynamically.

```bash
sudo pacman -S auto-cpufreq
sudo systemctl enable --now auto-cpufreq
```

---

## Baseline Security Checklist

What this system already has covered before any of the above:

| Feature | Status |
|---|---|
| LUKS full disk encryption | ✅ |
| Unified Kernel Image (UKI) | ✅ |
| Secure Boot (custom keys) | ✅ |
| Signed bootloader + UKI | ✅ |
| Hardened kernel parameters | ✅ |
| Secure Boot key backup | ✅ |
| Modern kernel (7.x) | ✅ |
| Firewall | ➡ add `ufw` |
| Data backup | ➡ add `restic` |

---

## Kernel Cmdline (LUKS system)

Current recommended `/etc/kernel/cmdline` for a LUKS-encrypted NVMe system with
Secure Boot and hardened parameters:

```
rd.luks.name=YOUR-LUKS-UUID=cryptroot root=/dev/mapper/cryptroot rw lockdown=confidentiality module.sig_enforce=1 slab_nomerge init_on_alloc=1 init_on_free=1 page_alloc.shuffle=1 randomize_kstack_offset=on vsyscall=none debugfs=off
```

Get your LUKS UUID with:

```bash
sudo cryptsetup luksUUID /dev/nvme0n1p2
```

After editing cmdline, always regenerate and re-sign:

```bash
sudo mkinitcpio -p linux
sudo sbctl sign -s /efi/EFI/Linux/arch-linux.efi
sudo sbctl verify
```

---

## Secure Boot Key Backup Location

sbctl stores keys at:

```
/var/lib/sbctl/keys/db/db.pem    ← signs bootloader and UKIs
/var/lib/sbctl/keys/KEK/KEK.pem  ← authorizes database updates
/var/lib/sbctl/keys/PK/PK.pem    ← root of trust
```

Back up the entire directory to an external drive:

```bash
sudo cp -r /var/lib/sbctl/ /run/media/youruser/USBNAME/sbctl-backup/
```

---

## 🖥 i3 Desktop Utilities & UI Stack

Core desktop utilities for an i3wm-based Arch Linux setup.

### Install Packages

```bash
sudo pacman -S dunst polybar rofi xss-lock i3lock ttf-jetbrains-mono-nerd
