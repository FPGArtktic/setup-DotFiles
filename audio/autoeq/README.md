# AutoEq impulses

Convolution impulses for Denon AH-D5200, AH-D7200 and AH-D9200 at 44.1 and
48 kHz, plus the parametric EQ they were generated from (`*.txt`, preamp
already baked into the impulse). Generated with [AutoEq](https://github.com/jaakkopasanen/AutoEq)
from oratory1990's measurements.

`setup-dotFiles.sh` installs them into `~/.local/share/autoeq/denon/`;
`autoeq D5200` (from `audio/bin/autoeq`) puts a convolver sink in front of
the headphone output. See `docs/AUDIO.md`.
