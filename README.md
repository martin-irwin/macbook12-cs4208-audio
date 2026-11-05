# macbook12-cs4208-audio

Internal speakers **and** the headphone jack on the 12-inch MacBook (2017,
`MacBook10,1`, Cirrus Logic CS4208), on Linux, **using the stock kernel
driver**. There's no out-of-tree driver to rebuild when the kernel updates.

- Speakers work.
- Headphones work.
- Plugging in or unplugging switches output instantly, without pausing your player.
- Volume control works on both outputs.

Tested on Omarchy (Arch), kernel `7.2.15`, PipeWire 1.6.9, MacBook10,1.
Other 12-inch MacBooks (MacBook9,1) use the same codec, but nobody has tested this
on one yet.

## Why the speakers are silent on Linux

There are two separate causes, and you need to fix both.

1. **A muted startup chime keeps the speaker amp off.** The speakers sit behind an
   external amplifier on a digital link. The Mac firmware powers that amp up only
   when the startup chime plays. If you muted the chime in macOS (Apple stores this
   in EFI NVRAM `SystemAudioVolume`; bit `0x80` means muted), the amp never powers
   on, and no driver can make sound. `chime-unmute.sh` fixes this.
2. **The stock driver never sets up the amp link.** `snd-hda-codec-cs420x` routes
   audio to the digital speaker pin (`0x1d` via converter `0x0a`), but it never
   sends the setup sequence the amp needs. The out-of-tree
   [macbook12-audio-driver](https://github.com/juicecultus/macbook12-audio-driver)
   replays macOS's sequence, but it has no headphone support.

## How this works

The stock driver stays loaded and handles the headphone jack and plug detection.
A small root service, `cs4208-speakerd`, sends the chip the macOS command sequences
when they're needed. It talks to the codec directly through the HDA hwdep interface
(`/dev/snd/hwC0D0`).

- **Playback starts, or headphones are unplugged:** the service replays macOS's
  speaker setup (`setup_a1534` + `play_a1534`, 381 commands, about 40 ms).
  - The setup is replayed each time the device opens because the codec power-saves
    after 1 s idle, which wipes it.
- **Headphones are plugged in during speaker playback:** the service replays
  macOS's own headphone switch (`headphones_a1534`, about 12 ms), with the GPIO
  pulses removed (see below).
- **Headphones are plugged in when playback starts:** the stock driver already has
  the headphones set up.
- **Event-driven:** the service watches `/dev/snd/pcmC0D0p` for opens (inotify) and
  subscribes to ALSA control events for jack changes. It uses no CPU when idle.
- **WirePlumber rule:**
  - It pins the output to 16-bit/44.1 kHz, the only format the amp accepts.
  - It turns on software volume (`api.alsa.soft-mixer`). The speaker path is
    digital and ignores the hardware `Master` control.
- **Fallback:** if a codec command fails, or the stream tag can't be found, the
  service cycles the card profile off and on. That makes the stock driver fully
  re-initialise the codec, at the cost of a gap of about 1.7 s.

## Findings that may save you time

- **GPIO4/5 pulses shut the speaker amp down.** macOS's headphone sequence pulses
  GPIO4/5 (`0x20 → 0x30 → 0x10 → 0x00`). This appears to be a pulse-coded command
  that shuts the speaker amp down, and only a cold boot (the chime) brings it back.
  `verbs/hp.verbs` has these writes removed, and GPIO0 alone gates the amp.
- **The headphone switch detaches converter `0x0a`.** After it runs, the stream tag
  has to be read from the headphone DAC (`0x02`) or remembered.
- **Vendor coef `0x1f` doesn't show whether the headphones work.** Under the stock
  driver it reads `0x400`; after the speaker setup it reads `0`, and you can't
  write it directly. It also stays `0` after the macOS headphone switch, even though
  the headphones then play.
- **Hardware volume does nothing on the speakers.** `Master`/`PCM` have no effect
  there, so use software volume.
- **`pactl suspend-sink` doesn't release the device while a client is streaming.**
  To make the codec actually power down, switch the card profile off.
- **The SPI keyboard driver is unrelated.** `macbook12-spi-driver` is a separate
  package and has nothing to do with audio.

## Install

```sh
# 1. Remove the out-of-tree speaker driver, if you installed it.
sudo dkms remove macbook12-audio-driver/0.1 --all   # or macbook12-audio/0.1

# 2. Un-mute the startup chime. The optional argument sets a quieter chime
#    (e8 = -24 dB; the encoding is unverified).
sudo ./chime-unmute.sh e8

# 3. Install the service, the command lists and your WirePlumber rule.
sudo ./install.sh

# 4. Power off and on (not restart), so the chime powers the amp.
```

Watch the service with `journalctl -u cs4208-speakerd -f`.

## Uninstall

```sh
sudo ./uninstall.sh
```

This leaves you on the plain stock driver, where headphones work and the speakers
are silent. Undo the chime change by writing the backup in `/var/tmp/` back, or by
re-muting it in macOS.

## Files

| Path | Installed to |
|---|---|
| `cs4208-speakerd` | `/usr/local/sbin/` |
| `verbs/{setup,play,hp}.verbs` | `/usr/local/share/cs4208/` |
| `systemd/cs4208-speakerd.service` | `/etc/systemd/system/` |
| `wireplumber/51-macbook-cs4208-speakers.conf` | `~/.config/wireplumber/wireplumber.conf.d/` |

## Credits

- The command sequences are extracted from
  [juicecultus/macbook12-audio-driver](https://github.com/juicecultus/macbook12-audio-driver).
  That project is based on
  [leifliddy/macbook12-audio-driver](https://github.com/leifliddy/macbook12-audio-driver)
  and [davidjo/snd_hda_macbookpro](https://github.com/davidjo/snd_hda_macbookpro).
  Those projects captured the macOS traces this relies on.
- The startup-chime / amp-power insight came from a community write-up on
  Omarchy/Arch for MacBook9,1/10,1.

## License

GPL-2.0-or-later. The verb sequences come from GPL-licensed kernel-driver code.
See `LICENSE`.
