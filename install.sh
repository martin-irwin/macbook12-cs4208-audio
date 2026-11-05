#!/bin/bash
# Install cs4208-speakerd for the MacBook10,1 (12-inch, 2017) on the stock kernel driver.
# Run as root:  sudo ./install.sh
set -euo pipefail
cd "$(dirname "$0")"
[ "$(id -u)" = 0 ] || { echo "run as root: sudo $0"; exit 1; }

model=$(cat /sys/class/dmi/id/product_name 2>/dev/null || true)
[ "$model" = "MacBook10,1" ] || echo "warning: tested on MacBook10,1 only (this is '$model')"

# The out-of-tree speaker driver must NOT be loaded: this needs the stock
# snd-hda-codec-cs420x (it handles the headphone jack).
if dkms status 2>/dev/null | grep -qiE 'macbook12-audio'; then
  echo "error: a macbook12-audio DKMS driver is registered; remove it first, e.g."
  echo "  dkms remove macbook12-audio/0.1 --all   (or macbook12-audio-driver/0.1)"
  exit 1
fi

# The speaker amp is only powered by the firmware if the startup chime is NOT muted.
V=/sys/firmware/efi/efivars/SystemAudioVolume-7c436110-ab2a-4bbb-a880-fe41995c9f82
if [ -r "$V" ] && [ $(( 0x$(od -An -tx1 -j4 -N1 "$V" | tr -d ' ') & 0x80 )) -ne 0 ]; then
  echo "warning: the startup chime is muted, so the speaker amp will stay off."
  echo "         run ./chime-unmute.sh, then power off and on."
fi

install -Dm755 cs4208-speakerd /usr/local/sbin/cs4208-speakerd
install -Dm644 -t /usr/local/share/cs4208 verbs/setup.verbs verbs/play.verbs verbs/hp.verbs
install -Dm644 systemd/cs4208-speakerd.service /etc/systemd/system/cs4208-speakerd.service
systemctl daemon-reload
systemctl enable --now cs4208-speakerd.service

# Per-user PipeWire/WirePlumber rule (16-bit/44.1 kHz + software volume)
user=${SUDO_USER:-}
if [ -n "$user" ]; then
  home=$(getent passwd "$user" | cut -d: -f6)
  install -Dm644 -o "$user" -g "$(id -gn "$user")" wireplumber/51-macbook-cs4208-speakers.conf \
    "$home/.config/wireplumber/wireplumber.conf.d/51-macbook-cs4208-speakers.conf"
  uid=$(id -u "$user")
  runuser -u "$user" -- env XDG_RUNTIME_DIR=/run/user/$uid systemctl --user restart wireplumber || true
  echo "installed WirePlumber rule for $user"
else
  echo "note: copy wireplumber/51-macbook-cs4208-speakers.conf to"
  echo "      ~/.config/wireplumber/wireplumber.conf.d/ and restart wireplumber"
fi
systemctl --no-pager --lines=3 status cs4208-speakerd.service || true
