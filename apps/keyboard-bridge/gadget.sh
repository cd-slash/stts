#!/usr/bin/env bash
# Raspberry Pi Zero 2 W: one USB cable carries a boot keyboard and private Ethernet.
set -euo pipefail

modprobe libcomposite
gadget=/sys/kernel/config/usb_gadget/stts_keyboard
test -d /sys/kernel/config/usb_gadget
test -n "$(ls /sys/class/udc)"
if [[ -e "$gadget/UDC" && -n "$(cat "$gadget/UDC")" ]]; then
  if [[ "$(cat "$gadget/idVendor")" == 0x1d6b &&
        "$(cat "$gadget/idProduct")" == 0x0104 &&
        "$(cat "$gadget/functions/hid.usb0/report_length")" == 8 &&
        -L "$gadget/configs/c.1/hid.usb0" && -L "$gadget/configs/c.1/ecm.usb0" ]]; then
    exit 0
  fi
  echo "An unexpected gadget is already bound; refusing to replace it" >&2
  exit 1
fi
mkdir -p "$gadget"
cd "$gadget"
rm -f configs/c.1/hid.usb0 configs/c.1/ecm.usb0
echo 0x1d6b > idVendor
echo 0x0104 > idProduct
echo 0x0200 > bcdUSB
mkdir -p strings/0x409
echo STTSKBD01 > strings/0x409/serialnumber
echo STTS > strings/0x409/manufacturer
echo 'STTS Keyboard' > strings/0x409/product
mkdir -p configs/c.1/strings/0x409
echo 'Keyboard and USB network' > configs/c.1/strings/0x409/configuration
echo 250 > configs/c.1/MaxPower

mkdir -p functions/hid.usb0
echo 1 > functions/hid.usb0/protocol
echo 1 > functions/hid.usb0/subclass
echo 8 > functions/hid.usb0/report_length
# Standard US boot-keyboard descriptor matching bridge.py's 8-byte reports.
printf '\x05\x01\x09\x06\xa1\x01\x05\x07\x19\xe0\x29\xe7\x15\x00\x25\x01\x75\x01\x95\x08\x81\x02\x95\x01\x75\x08\x81\x01\x95\x05\x75\x01\x05\x08\x19\x01\x29\x05\x91\x02\x95\x01\x75\x03\x91\x01\x95\x06\x75\x08\x15\x00\x25\x65\x05\x07\x19\x00\x29\x65\x81\x00\xc0' > functions/hid.usb0/report_desc
ln -s functions/hid.usb0 configs/c.1/hid.usb0

mkdir -p functions/ecm.usb0
echo '02:4b:42:44:00:01' > functions/ecm.usb0/host_addr
echo '02:4b:42:44:00:02' > functions/ecm.usb0/dev_addr
ln -s functions/ecm.usb0 configs/c.1/ecm.usb0

echo "$(ls /sys/class/udc | head -n1)" > UDC
