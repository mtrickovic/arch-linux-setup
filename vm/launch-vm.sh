#!/usr/bin/env bash
set -euo pipefail

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

usage() {
  cat <<EOF
Usage: $0 [OPTIONS] <disk_name>

Options:
  -s, --ssh     Run headless and daemonized (no display, no cdrom);
                access the VM via SSH once it's up
  -h, --help    Show this help message
EOF
}

parse_args() {
  local -n __pa_disk="$1"
  local -n __pa_ssh="$2"
  shift 2

  while [[ $# -gt 0 ]]; do
    case "$1" in
    -s | --ssh)
      __pa_ssh=1
      shift
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    -*)
      die "Unknown option: $1"
      ;;
    *)
      [[ -z "$__pa_disk" ]] || die "Only one positional argument allowed"
      __pa_disk="$1"
      shift
      ;;
    esac
  done

  if [[ -z "$__pa_disk" ]]; then
    die "Usage: $0 <disk_name>"
  fi
}

main() {
  local disk=""
  local ssh_enabled=0
  parse_args disk ssh_enabled "$@"

  if [[ ! -f "$disk" ]]; then
    die "Disk file not found '$disk'"
  fi

  if ! ip link show tap0 &>/dev/null; then
    die "tap0 does not exist. Create it first, e.g.:
  sudo ip tuntap add dev tap0 mode tap
  sudo ip addr add 192.168.100.1/24 dev tap0
  sudo ip link set tap0 up"
  fi

  local -a opts=(
    -machine q35
    -accel kvm
    -m 8G
    -smp 4

    -drive "file=${disk},format=qcow2,if=none,id=nvme0"
    -device "nvme,drive=nvme0,serial=deadbeef"

    -drive "if=pflash,format=raw,readonly=on,file=${OVMF_CODE}"
    -drive "if=pflash,format=raw,file=${OVMF_VARS}"

    # Host <-> VM
    -netdev tap,id=net0,ifname=tap0,script=no,downscript=no
    -device virtio-net-pci,netdev=net0

    # Internet
    -netdev user,id=net1
    -device virtio-net-pci,netdev=net1
  )

  if [[ $ssh_enabled -eq 1 ]]; then
    opts+=(
      -daemonize
      -pidfile "/tmp/qemu-${disk##*/}.pid"
      -display none
    )
  else
    opts+=(
      -vga qxl
      -cdrom "$ISO"
    )
  fi

  qemu-system-x86_64 "${opts[@]}"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
