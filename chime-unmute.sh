#!/bin/bash
# Un-mute the Mac startup chime (EFI NVRAM). The internal speaker amp is only
# powered up by the firmware when the chime plays, so this is required for speakers.
# Usage: sudo ./chime-unmute.sh [dB-byte]
#   dB-byte: optional SystemAudioVolumeDB value (signed dB, hex), e.g. e8 = -24 dB
#            for a quieter chime. Unverified encoding; it worked on one machine.
set -euo pipefail
[ "$(id -u)" = 0 ] || { echo "run as root: sudo $0"; exit 1; }
G=7c436110-ab2a-4bbb-a880-fe41995c9f82
dir=/sys/firmware/efi/efivars
write() {  # name, value-byte (attributes must be 07 00 00 00; the stored 0x80000007 is rejected)
  local f=$dir/$1-$G t; t=$(mktemp)
  [ -e "$f" ] && cp -n "$f" "/var/tmp/$1.backup.bin" || true
  printf "\x07\x00\x00\x00\x$2" > "$t"
  chattr -i "$f" 2>/dev/null || true
  dd if="$t" of="$f" bs=5 count=1 status=none
  chattr +i "$f" 2>/dev/null || true
  echo "$1 = $(od -An -tx1 -j4 "$f")"
}
write SystemAudioVolume 20          # bit 0x80 = mute; 0x20 = un-muted
[ $# -ge 1 ] && write SystemAudioVolumeDB "$1"
echo "power off and on (not restart) to apply"
