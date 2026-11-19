#!/usr/bin/env bash
# Flash PetaLinux WIC to MicroSD, overlay FNN BOOT.BIN, enable SSH + static IP.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT/board/lib.sh"
load_config

BOOT_BIN="${1:-$OUT_DIR/BOOT.BIN}"
IP="${FNN_ETH_IP:-192.168.178.10}"
GW="${FNN_ETH_GW:-192.168.178.1}"
PASS="${BOARD_PASS:-fnn}"

if [[ ! -b "$SD_DEV" ]]; then
  echo "Block device not found: $SD_DEV" >&2
  exit 1
fi
if [[ ! -f "$WIC_IMG" ]]; then
  echo "Missing WIC image: $WIC_IMG" >&2
  echo "Download PetaLinux 2024.2 ZCU104 sd_image .wic.xz, decompress, set WIC_IMG." >&2
  exit 1
fi
if [[ ! -f "$BOOT_BIN" ]]; then
  echo "Missing $BOOT_BIN — run board/build_boot.sh first" >&2
  exit 1
fi

echo "About to wipe $SD_DEV and write PetaLinux + FNN BOOT.BIN"
echo "  SSH will be root@$IP  password=$PASS"
echo "Ctrl-C within 5s to abort..."
sleep 5

sudo umount "${SD_DEV}p"* 2>/dev/null || true
echo "Writing WIC..."
sudo dd if="$WIC_IMG" of="$SD_DEV" bs=4M status=progress conv=fsync
sudo sync
sleep 2
sudo partprobe "$SD_DEV" || true
sleep 2

MNT=$(mktemp -d)
sudo mount "${SD_DEV}p1" "$MNT"
sudo cp -v "$BOOT_BIN" "$MNT/BOOT.BIN"
sudo umount "$MNT"

sudo mount "${SD_DEV}p2" "$MNT"
sudo FNN_ETH_IP="$IP" FNN_ETH_GW="$GW" FNN_ROOT_PASS="$PASS" \
  "$ROOT/board/enable_ssh.sh" "$MNT"
sudo umount "$MNT"
rmdir "$MNT"
sync

echo
echo "Done. Eject SD → ZCU104, SW6=ON OFF OFF OFF, Ethernet, power on."
echo "  ssh root@$IP   (password $PASS)"
echo "Note: if DHCP wins, find host zynqmp-zcu104-sdt-full on your LAN."
