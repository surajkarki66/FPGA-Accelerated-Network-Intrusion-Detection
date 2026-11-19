#!/usr/bin/env bash
# Patch a mounted PetaLinux rootfs for root SSH + static Ethernet.
# Usage: sudo FNN_ETH_IP=192.168.178.10 ./enable_ssh.sh /mnt/root
set -euo pipefail

ROOT=${1:?mounted rootfs path required}
IP=${FNN_ETH_IP:-192.168.178.10}
PREFIX=${FNN_ETH_PREFIX:-24}
GW=${FNN_ETH_GW:-192.168.178.1}
PASS=${FNN_ROOT_PASS:-fnn}

[[ -d "$ROOT/etc" ]] || {
  echo "Not a rootfs: $ROOT" >&2
  exit 1
}

echo "Patching $ROOT  SSH root/$PASS  eth $IP/$PREFIX gw $GW"

SSHD="$ROOT/etc/ssh/sshd_config"
if [[ -f "$SSHD" ]]; then
  sed -i -E \
    -e 's/^#?PermitRootLogin.*/PermitRootLogin yes/' \
    -e 's/^#?PasswordAuthentication.*/PasswordAuthentication yes/' \
    -e 's/^#?PermitEmptyPasswords.*/PermitEmptyPasswords no/' \
    "$SSHD"
  grep -q '^PermitRootLogin' "$SSHD" || echo 'PermitRootLogin yes' >>"$SSHD"
  grep -q '^PasswordAuthentication' "$SSHD" || echo 'PasswordAuthentication yes' >>"$SSHD"
fi

mkdir -p "$ROOT/etc/systemd/system/sockets.target.wants"
ln -sfn /usr/lib/systemd/system/sshd.socket \
  "$ROOT/etc/systemd/system/sockets.target.wants/sshd.socket"

HASH=$(openssl passwd -6 "$PASS")
python3 - "$ROOT/etc/shadow" "$HASH" <<'PY'
import sys
path, hash_ = sys.argv[1], sys.argv[2]
lines = open(path).read().splitlines()
out = []
for line in lines:
    if line.startswith("root:"):
        parts = line.split(":")
        parts[1] = hash_
        out.append(":".join(parts))
    else:
        out.append(line)
open(path, "w").write("\n".join(out) + "\n")
PY

# Interface name is end0 on 2024.2 ZCU104 SDT images (not eth0).
mkdir -p "$ROOT/etc/systemd/network"
cat >"$ROOT/etc/systemd/network/10-end-static.network" <<EOF
[Match]
Name=end0
Type=ether

[Network]
Address=$IP/$PREFIX
Gateway=$GW
DNS=8.8.8.8
EOF

# Also match eth0 if a different image uses that name
cat >"$ROOT/etc/systemd/network/10-eth-static.network" <<EOF
[Match]
Name=eth0
Type=ether

[Network]
Address=$IP/$PREFIX
Gateway=$GW
DNS=8.8.8.8
EOF

mkdir -p "$ROOT/etc/systemd/system/multi-user.target.wants"
ln -sfn /usr/lib/systemd/system/systemd-networkd.service \
  "$ROOT/etc/systemd/system/multi-user.target.wants/systemd-networkd.service"

sync
echo "Done."
