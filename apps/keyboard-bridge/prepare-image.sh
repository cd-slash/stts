#!/usr/bin/env bash
# Stage a CLEAN Raspberry Pi OS Lite image for first boot as USB Ethernet.
# Does not write an SD card or activate the HID keyboard yet.
set -euo pipefail
if [[ $# -ne 2 || ! -f "$1" || ! -f "$2" ]]; then
  echo "Usage: $0 /path/to/uncompressed-raspios.img /path/to/ssh.pub" >&2
  exit 2
fi
image=$(realpath "$1")
mapfile -t keys < "$2"
[[ ${#keys[@]} -eq 1 ]] && ssh-keygen -lf "$2" >/dev/null &&
  [[ "${keys[0]}" == ssh-*\ * || "${keys[0]}" == ecdsa-*\ * || "${keys[0]}" == sk-*\ * ]] ||
  { echo "Expected exactly one valid SSH public key" >&2; exit 2; }
key_yaml=$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "${keys[0]}")
dir=$(cd "$(dirname "$0")" && pwd)
loop=""
base=""
cleanup() {
  status=$?
  trap - EXIT
  if [[ -n "$base" ]]; then
    mountpoint -q "$base/root" && umount "$base/root" || true
    mountpoint -q "$base/boot" && umount "$base/boot" || true
  fi
  [[ -z "$loop" ]] || losetup -d "$loop" || echo "Detach loop $loop manually" >&2
  [[ -z "$base" ]] || rmdir "$base/root" "$base/boot" "$base" 2>/dev/null || true
  exit "$status"
}
trap cleanup EXIT
loop=$(losetup -fP --show "$image")
base=$(mktemp -d /mnt/stts-keyboard.XXXXXX)
mkdir "$base/root" "$base/boot"
mount "${loop}p2" "$base/root"
mount "${loop}p1" "$base/boot"
root="$base/root"
boot="$base/boot"

grep -q 'VERSION_CODENAME=trixie' "$root/etc/os-release"
grep -q '^\[all\]' "$boot/config.txt"
test -x "$root/usr/bin/cloud-init"
test -L "$root/etc/systemd/system/cloud-init.target.wants/cloud-init-local.service"
grep -q 'datasource_list: \[ NoCloud, None \]' "$root/etc/cloud/cloud.cfg.d/99_raspberry-pi.cfg"
grep -q 'seedfrom: file:///boot/firmware' "$root/etc/cloud/cloud.cfg.d/99_raspberry-pi.cfg"
grep -q '^dsmode: local$' "$boot/meta-data"
grep -q '^instance_id:' "$boot/meta-data"
grep -qx 'dtoverlay=dwc2,dr_mode=peripheral' "$boot/config.txt" ||
  echo 'dtoverlay=dwc2,dr_mode=peripheral' >> "$boot/config.txt"

# First boot: g_ether gives a wired SSH path without knowing Wi-Fi credentials.
cat > "$root/etc/modules-load.d/stts-usb-network.conf" <<'EOF'
dwc2
g_ether
EOF
cat > "$root/etc/modprobe.d/stts-usb-network.conf" <<'EOF'
options g_ether host_addr=02:4b:42:44:00:01 dev_addr=02:4b:42:44:00:02
EOF
rm -f "$root/etc/NetworkManager/system-connections/stts-usb.nmconnection"
install -d "$root/etc/NetworkManager/conf.d"
install -m 0644 "$dir/stts-usb-unmanaged.conf" "$root/etc/NetworkManager/conf.d/stts-usb-unmanaged.conf"
# Do not let cloud-init generate an overlapping DHCP connection for usb0.
cat > "$root/etc/cloud/cloud.cfg.d/99-stts-network.cfg" <<'EOF'
network: {config: disabled}
EOF
cat > "$boot/user-data" <<EOF
#cloud-config
hostname: stts-keyboard-1
manage_etc_hosts: true
ssh_pwauth: false
users:
  - name: stts
    gecos: STTS keyboard administrator
    groups: [adm, sudo]
    shell: /bin/bash
    lock_passwd: true
    sudo: ALL=(ALL) NOPASSWD:ALL
    ssh_authorized_keys:
      - $key_yaml
EOF
touch "$boot/ssh"
install -d "$root/etc/systemd/system/multi-user.target.wants"
ln -sfn /usr/lib/systemd/system/ssh.service "$root/etc/systemd/system/multi-user.target.wants/ssh.service"
install -d -m 0755 "$root/etc/ssh/sshd_config.d"
cat > "$root/etc/ssh/sshd_config.d/60-stts-keyboard.conf" <<'EOF'
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin no
PubkeyAuthentication yes
EOF

# Stage services; only enable them after SSH over the private USB link works.
install -d -m 0755 "$root/opt/stts-keyboard" "$root/usr/local/sbin"
install -m 0644 "$dir/bridge.py" "$root/opt/stts-keyboard/bridge.py"
install -m 0755 "$dir/gadget.sh" "$root/usr/local/sbin/stts-keyboard-gadget"
install -m 0644 "$dir/stts-keyboard-gadget.service" "$dir/stts-keyboard-bridge.service" "$dir/stts-keyboard-usb-fallback.service" "$root/etc/systemd/system/"
install -m 0644 "$dir/stts-keyboard-usb.service" "$root/etc/systemd/system/"
install -m 0644 "$dir/99-stts-hid.rules" "$root/etc/udev/rules.d/"
ln -sfn /etc/systemd/system/stts-keyboard-usb.service "$root/etc/systemd/system/multi-user.target.wants/stts-keyboard-usb.service"
sync
echo "Staged USB-network bootstrap and disabled HID services in $image"
