#!/usr/bin/env bash
set -euo pipefail

# minimal starting point — no path/existence checks yet

# readonly OVMF_CODE="/usr/share/edk2/x64/OVMF_CODE.4m.fd"
readonly OVMF_CODE="/usr/share/OVMF/x64/OVMF_CODE.secboot.4m.fd"
readonly OVMF_VARS="/usr/share/edk2/x64/OVMF_VARS.4m.fd"
readonly ISO="archlinux-x86_64.iso"

log_info() { echo "[INFO] $*"; }
log_error() { echo "[ERROR] $*" >&2; }
die() {
  log_error "$*"
  exit 1
}

main() {
  local disk="${1:-}"
  [[ -z $disk ]] && die "Usage: $0 <disk_name>"

  local -a opts=(
    -machine q35
    -accel kvm
    -m 8G
    -smp 4
    -vga qxl

    -drive "file=${disk},format=qcow2,if=none,id=nvme0"
    -device "nvme,drive=nvme0,serial=deadbeef"

    -drive "if=pflash,format=raw,readonly=on,file=${OVMF_CODE}"
    -drive "if=pflash,format=raw,file=${OVMF_VARS}"

    -cdrom "$ISO"
  )

  qemu-system-x86_64 "${opts[@]}"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
