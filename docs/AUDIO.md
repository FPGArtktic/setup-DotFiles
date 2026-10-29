# Audio: what the audio step installs, and why

The `audio` step of `setup-dotFiles.sh` installs a PipeWire/WirePlumber profile tuned for USB DACs,
an AutoEq switcher for Denon headphones, and a drop logger for the Q Acoustics M20. This page is
the reasoning behind it. Most of it was learned the hard way.

## 1 The hardware it was written for

| Device | Link | Hardware formats | Rates |
|---|---|---|---|
| **Q Acoustics M20** (`0d8c:0314`) | USB, high speed | S16_LE, **S24_3LE** | 44.1 / 48 / 88.2 / 96 / 176.4 / **192 kHz** |
| **FiiO E10** (`1852:7022`) | USB, full speed | S16_LE, **S24_3LE** | 32 / 44.1 / 48 / 96 kHz |
| onboard HDA codec, HDMI | PCI | S32_LE | whatever the codec reports |

Identify outputs by `node.name`, never by the numeric id: the ids change on every PipeWire restart.

```
alsa_output.usb-C-Media_Electronics_Inc._Q_Acoustics_M20-00.analog-stereo
alsa_output.usb-FIIO_FiiO_USB_DAC-E10-01.analog-stereo
alsa_output.pci-<bus>.analog-stereo
```

Use the M20 over **USB**, not through a monitor's HDMI audio and the AUX input. USB goes straight
into the speakers' converter, 24 bits at up to 192 kHz. The HDMI path goes through the monitor's
DAC and an analog cable first, and then the M20 has to digitise it again.

## 2 What is installed

**`~/.config/pipewire/pipewire.conf.d/99-audiophile.conf`**: `allowed-rates` 44.1-192 kHz, so a
card runs at the native rate of the material instead of everything being resampled to 48 kHz.
PipeWire trims the list to what each card supports, so one list fits every card. Quantum 32-2048.

**`~/.config/wireplumber/wireplumber.conf.d/99-audiophile.conf`**: two things for every
`alsa_output.*`:
- `resample.quality = 10`, which only matters when resampling cannot be avoided
- `session.suspend-timeout-seconds = 0`, because otherwise the M20 clicks its relay on wake-up and
  loses the start of the track

**`~/.local/bin/autoeq`** and **`~/.local/share/autoeq/denon/`**: convolution EQ for Denon AH-D5200,
D7200 and D9200 (AutoEq, oratory1990 measurements). It is off by default.

```sh
autoeq sinks            # the analog outputs it can play to
autoeq D5200            # EQ in front of the headphone output
autoeq status
autoeq off
AUTOEQ_SINK=alsa_output.usb-FIIO_FiiO_USB_DAC-E10-01.analog-stereo autoeq D7200
```

Without `AUTOEQ_SINK` it uses the onboard analog output, or else the first analog output that is
not HDMI.

**`~/.local/bin/m20-dropwatch`**: logs to `~/audio-dropouts.log` every time the M20 drops off the
bus, together with the rate and format it had a moment before. It also logs rate changes, PCM
closes, USB stream state and clock excursions. It finds the M20's port and ALSA card by USB id, so
it follows the device to any socket. Start it with `setsid -f m20-dropwatch` and read the
summary with `m20-dropwatch --report`.

## 3 Rules

1. **Never force `audio.format` globally.** A WirePlumber rule with `audio.format = "S32LE"` on
   every `alsa_output.*` once removed both USB DACs. They offer only S16_LE and S24_3LE, so no ALSA
   node was created for them (`spa.alsa: error pcm info: No such device`), and only HDMI was left.
   The device simply vanishes from the output list without a readable error. If something really
   has to be forced, match one `node.name`.
2. **Verify through `hw_params`, not the mixer.** `wpctl status` shows what PipeWire believes.
   `/proc/asound/cardN/pcm0p/sub0/hw_params` shows what the hardware actually gets. Read it while
   something is playing, because a closed PCM reads `closed`.
3. **Fewer entries are better.** Almost every real improvement came from *removing* a forced
   setting and letting PipeWire negotiate. What is left adds something: `allowed-rates`,
   `resample.quality`, and no suspend.

## 4 Volume

Neither USB DAC has a hardware volume control. The M20's USB mixer has only `PCM Playback Switch`
(mute), and the E10 has a knob. Any software volume other than 1.00 is therefore digital
attenuation that costs resolution: 0.21 is about -13 dB, more than two bits out of 24. Keep the
software at 1.00 and set the volume with the M20's remote or the E10's knob:

```sh
# turn the speakers down first - this is loud
wpctl set-volume <id> 1.0
```

Above 1.00 is digital gain and clips the peaks.

## 5 Trap: the M20 is silent although the sink is RUNNING

The symptom: the sink is `RUNNING`, `hw_params` shows an open `S24_3LE` PCM, and nothing comes out.
The hardware mute (`PCM Playback Switch`, an `INV_BOOLEAN`) was never written to the device.
PipeWire can report "unmuted" without having written it, so toggle it both ways:

```sh
wpctl set-mute <id-M20> 1 && wpctl set-mute <id-M20> 0
amixer -c <card> set 'PCM Playback' unmute      # alsa-utils
```

`alsa-utils` (on the package list) also brings `alsa-restore.service`, which restores the mixer
state at boot.

## 6 Sample formats, briefly

| Format | Bytes per sample | What it is |
|---|---|---|
| `S16_LE` | 2 | 16-bit signed, CD format |
| `S24_3LE` | 3 | 24 bits packed into 3 bytes |
| `S32_LE` | 4 | 32-bit container; HDA uses it even when the converter resolves fewer bits |

PipeWire mixes in 32-bit float and converts to each card's own format only at the very end,
separately for every output. `S32_LE` on an HDA codec is **not** better than `S24_3LE` on the M20.
It is just a wider container. There is nothing to choose by hand, because PipeWire reads the
descriptors (`/proc/asound/cardN/stream0`) and takes the deepest format offered.

## 7 Cheat sheet

```sh
wpctl status                     # what is seen, what is default
wpctl set-default <id>
wpctl inspect <id>               # format, resampler, suspend
pw-metadata -n settings          # active clock and allowed-rates

# which PCMs are open, and in what format:
for f in /proc/asound/card*/pcm*p/sub0/hw_params; do
  v=$(cat "$f"); [ "$v" != closed ] && echo "== $f" && echo "$v"; done

cat /proc/asound/cardN/stream0   # what a USB card can do
cat /proc/asound/cardN/usbmixer  # whether it has a hardware volume

systemctl --user restart pipewire pipewire-pulse wireplumber
journalctl --user -u wireplumber -b | grep -iE 'error|fail'
```
