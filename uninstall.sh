#!/bin/bash
# Remove cs4208-speakerd. Leaves the plain stock driver (headphones keep working).
set -euo pipefail
[ "$(id -u)" = 0 ] || { echo "run as root: sudo $0"; exit 1; }
systemctl disable --now cs4208-speakerd.service 2>/dev/null || true
rm -f /etc/systemd/system/cs4208-speakerd.service /usr/local/sbin/cs4208-speakerd
rm -rf /usr/local/share/cs4208
systemctl daemon-reload
user=${SUDO_USER:-}
if [ -n "$user" ]; then
  home=$(getent passwd "$user" | cut -d: -f6)
  rm -f "$home/.config/wireplumber/wireplumber.conf.d/51-macbook-cs4208-speakers.conf"
  runuser -u "$user" -- env XDG_RUNTIME_DIR=/run/user/$(id -u "$user") systemctl --user restart wireplumber || true
fi
echo "removed"
