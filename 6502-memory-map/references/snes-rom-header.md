# SNES ROM Header & ROM Files

Read **Quick facts** first. That's enough to locate the header, tell the
cartridge layout apart, and spot an SA-1 cart. The later sections are full
reference tables for tool, emulator, or patch work.

Contents: [Quick facts](#quick-facts) · [ROM files](#rom-files) ·
[Header fields](#header-fields) · [Map mode](#ffd5--map-mode) ·
[Chipset](#ffd6--chipset) · [Extended header](#extended-header-ffb0-ffbf) ·
[Region](#ffd9--region) · [Checksum](#checksum) ·
[Detecting the layout](#detecting-the-layout) ·
[Worked examples](#worked-examples)

## Quick facts

- The header is at **CPU `$00:FFC0-$FFDF`**. An extended header sits at
  `$FFB0-$FFBF` when `$FFDA` = `$33`, and the vectors follow at
  `$FFE0-$FFFF`. The hardware never reads the header; emulators, flashcarts
  and the game itself (as ordinary ROM data) do.
- Its offset in an unheadered file depends on the layout:

  | Layout | Header at file offset |
  |--------|-----------------------|
  | LoROM | `$007FC0` |
  | HiROM | `$00FFC0` |
  | ExHiROM | `$40FFC0` |
  | ExLoROM (unofficial; map byte still `$20`/`$30`) | `$407FC0` |

  Add `$200` if the file has a copier header (file size mod 1024 = 512).
- **`$FFD5` = `001smmmm`**:
  - `s` = 1 means FastROM.
  - `mmmm`: `0` LoROM, `1` HiROM, `2` S-DD1, `3` SA-1, `5` ExHiROM, `A`
    SPC7110.

  So `$20`/`$30` are LoROM, `$21`/`$31` HiROM, `$23` SA-1 and `$25`/`$35`
  ExHiROM. "Mode 20/21" is shorthand for this byte.
- **`$FFD6` chipset**: a high nibble of `3` means SA-1 (e.g. `$34`, `$35`). If
  you see that, use the 6502-snes-sa1 skill.

## ROM files

- Extensions: **`.sfc`** (most common), `.smc`, and less often `.fig`/`.swc`.
  The extension doesn't tell you whether a copier header is present.
- **Copier ("SMC") header**: 512 bytes that some copier devices prepend. It is
  *not* the internal ROM header.
  - Common layout: bytes 0-1 = ROM size in 8 KiB units (little-endian),
    byte 2 = copier-specific type flags, the rest zero.
  - Detect it by file size mod 1024: `0` = none, `512` = header present,
    anything else = malformed or truncated. Alternatively, look for a valid
    internal header at the three normal offsets + `$200`.
  - Unheadered files are the modern norm. Patches (e.g. IPS) target one
    variant or the other, so a patch applied to the wrong variant corrupts
    code.
- **Data order** (unheadered): the cartridge ROM in linear order.
  - LoROM: 32 KiB banks, file `$000000` = CPU `$80:8000` (= `$00:8000`).
  - HiROM: 64 KiB banks, file `$000000` = CPU `$C0:0000`.
  - ExHiROM: 64 KiB banks from `$C0:0000`; after 4 MiB the file continues at
    `$40:0000`.
- Sizes need not be a power of two, but should be a sum of two (e.g. 3 MiB =
  2 + 1). See [Checksum](#checksum) for how such files mirror.

## Header fields

All addresses are CPU addresses in bank `$00`. Multi-byte values are
little-endian.

| Address | Size | Field |
|---------|------|-------|
| `$FFC0` | 21 | Title, ASCII `$20-$7E`, padded with spaces |
| `$FFD5` | 1 | Map mode + speed (below) |
| `$FFD6` | 1 | Chipset: RAM, battery, coprocessor (below) |
| `$FFD7` | 1 | ROM size = `1 << n` KiB, rounded up to a power of two (`$08` = 256 KiB, `$0A` = 1 MiB, `$0B` = 2 MiB, `$0C` = 4 MiB, `$0D` = 8 MiB) |
| `$FFD8` | 1 | Cart RAM size = `1 << n` KiB, `0` = none (`$01` = 2 KiB, `$03` = 8 KiB, `$05` = 32 KiB) |
| `$FFD9` | 1 | Region / country, which implies NTSC or PAL (below) |
| `$FFDA` | 1 | Developer (licensee) ID; **`$33` = extended header present** |
| `$FFDB` | 1 | ROM version (0 = first release) |
| `$FFDC` | 2 | Checksum complement (= checksum XOR `$FFFF`) |
| `$FFDE` | 2 | Checksum |
| `$FFE0` | 32 | Interrupt vectors; see `references/65816.md` in the 6502-instruction-set skill |

The reset vector is at `$FFFC`. Execution starts there in emulation mode, with
PBR = DBR = `$00`.

## `$FFD5` — map mode

```
001smmmm
   s     = speed: 0 = SlowROM, 1 = FastROM (the game may set $420D bit 0)
    mmmm = 0 LoROM, 1 HiROM, 2 S-DD1, 3 SA-1, 5 ExHiROM, A SPC7110
```

| Byte | Meaning | Example game |
|------|---------|--------------|
| `$20` | LoROM | Final Fantasy IV (1 MiB) |
| `$21` | HiROM | Final Fantasy V (2 MiB) |
| `$23` | SA-1 | Super Mario RPG (4 MiB) |
| `$30` | LoROM + FastROM | Ultima VII (1.5 MiB) |
| `$31` | HiROM + FastROM | Final Fantasy VI (3 MiB) |
| `$32` | S-DD1 | Star Ocean (6 MiB) |
| `$35` | ExHiROM + FastROM | Tales of Phantasia (6 MiB); the only other commercial ExHiROM game is Daikaijū Monogatari 2 |

ExLoROM is an unofficial layout and has no code of its own; its header says
LoROM (`$20`/`$30`). Recognize it by the header sitting at file `$407FC0`,
which is what bsnes does. It appears only in ROM hacks, and emulator support
is inconsistent. See `snes-memory.md` for its layout.

## `$FFD6` — chipset

| Low nibble | Contents |
|------------|----------|
| `0` | ROM only |
| `1` | ROM + RAM |
| `2` | ROM + RAM + battery |
| `3` | ROM + coprocessor |
| `4` | ROM + coprocessor + RAM |
| `5` | ROM + coprocessor + RAM + battery |
| `6` | ROM + coprocessor + battery |

A battery (save RAM) is present when the low nibble is `2`, `5` or `6`.

| High nibble (when a coprocessor is present) | Coprocessor |
|---------------------------------------------|-------------|
| `0` | DSP (DSP-1/2/3/4) |
| `1` | GSU (Super FX) |
| `2` | OBC1 |
| `3` | **SA-1** |
| `4` | S-DD1 |
| `5` | S-RTC |
| `E` | Other (Super Game Boy, Satellaview) |
| `F` | Custom: see `$FFBF` (`$00` SPC7110, `$01` ST010/ST011, `$02` ST018, `$03` CX4) |

## Extended header (`$FFB0-$FFBF`)

It's present when `$FFDA` = `$33`. Some early games instead mark `$FFBF` alone
as valid by setting the last title byte (`$FFD4`) to `$00`.

| Address | Size | Field |
|---------|------|-------|
| `$FFB0` | 2 | Maker code, ASCII uppercase |
| `$FFB2` | 4 | Game code, ASCII uppercase; the last character is the region letter (below) |
| `$FFB6` | 6 | Reserved, zero |
| `$FFBC` | 1 | Expansion flash size = `1 << n` KiB |
| `$FFBD` | 1 | Expansion RAM size = `1 << n` KiB, mainly for the GSU (`$01` = 16 kbit, `$03` = 64 kbit, `$05` = 256 kbit, `$06` = 512 kbit, `$07` = 1 Mbit) |
| `$FFBE` | 1 | Special version, usually 0 |
| `$FFBF` | 1 | Chipset subtype, used when `$FFD6` is `$Fx` |

For the **SA-1**, `$FFBD` must be `$00`, and the BW-RAM size goes in `$FFD8`.
If the RAM size you need isn't in the `$FFBD` list, use the next size up.
(bsnes treats Star Fox, a GSU game with no extended header, as having 32 KiB
of expansion RAM anyway.)

## `$FFD9` — region

| Code | Region | Letter | bsnes video |
|------|--------|--------|-------------|
| `$00` | Japan | J | NTSC |
| `$01` | North America | E | NTSC |
| `$02` | Europe (incl. Oceania, Asia originally) | P | PAL |
| `$03` | Scandinavia | W | PAL |
| `$04` | Finland | — | PAL |
| `$05` | Denmark | — | PAL |
| `$06` | France | F | PAL |
| `$07` | Netherlands | H | PAL |
| `$08` | Spain | S | PAL |
| `$09` | Germany / Austria / Switzerland | D | PAL |
| `$0A` | Italy | I | PAL |
| `$0B` | China / Hong Kong (bsnes: Taiwan) | C | NTSC |
| `$0C` | Indonesia | — | PAL |
| `$0D` | South Korea | K | NTSC |
| `$0E` | Common | A | PAL |
| `$0F` | Canada | N | NTSC |
| `$10` | Brazil (also the Nintendo Gateway System, letter G) | B | NTSC |
| `$11` | Australia | U | PAL |
| `$12-$14` | Other variations | X / Y / Z | PAL |

The wiki only commits to `$00`/`$01` being NTSC and says most others are PAL.
The column above follows bsnes (`videoRegion`). `$04`, `$05` and `$0C` come
from uCON64 and have no letter.

## Checksum

The checksum is a 16-bit sum of every byte of the ROM, with overflow
discarded. It is computed over a power-of-two size equal to what `$FFD7`
declares.

**Non-power-of-two ROMs.** A cart built from two chips (e.g. 2 MiB + 1 MiB)
mirrors the smaller chip in the memory map. Dumps usually leave the mirror out.
To rebuild the full image:

1. Take the largest power of two ≤ the data size as the first part.
2. If data remains after that:
   1. Pad the remainder with `$00` up to the next power of two.
   2. Repeat the remainder until it is as big as the first part.

The common 2:1 case (3 MiB) works out to "double the last third". Files that
need padding are usually homebrew. Pad your own ROMs to a clean boundary,
because emulators disagree on what to pad with.

**Computing it:**

1. Put `$0000` in the checksum field and `$FFFF` in the complement field. They
   sum to the same total as any final checksum/complement pair, so the result
   stays valid once the real values are written in.
2. Sum every byte of the prepared image into a 16-bit value, discarding
   overflow.
3. Store the sum at `$FFDE` and `sum XOR $FFFF` at `$FFDC`.

A copier header is never part of the sum.

## Detecting the layout

Score each candidate header location (`$7FC0`, `$FFC0`, `$40FFC0`, `$407FC0`,
and each +`$200`). bsnes and Snes9x use roughly these rules:

- The stored checksum matches the computed one. This is the strongest
  signal; some flashcarts use it alone. Hacks and homebrew often leave it
  wrong, though.
- Checksum + complement = `$FFFF`.
- The map-mode byte matches the location (`$20` at `$7FC0`, `$21` at `$FFC0`).
- The declared ROM size isn't smaller than the file.
- The reset vector is ≥ `$8000`. Anything below can't be ROM.
- The first opcode at the reset vector:
  - is likely if it's `SEI` `$78`, `CLC` `$18`, `SEC` `$38`, `STZ abs` `$9C`,
    `JMP` `$4C` or `JML` `$5C`;
  - is plausible if it's `REP`, `SEP`, `LDA`/`LDX`/`LDY`, `JSR` or `JSL`;
  - is unlikely if it's `BRK` `$00`, `COP` `$02`, `STP` `$DB`, `WDM` `$42` or
    `$FF`, or a return (`RTI`/`RTS`/`RTL`).
- The ROM and RAM sizes are plausible, and the title is printable ASCII.

## Worked examples

**Final Fantasy IV (US "FINAL FANTASY II"), LoROM, unheadered.** File
`$7FC0`:

```
7FC0  46 49 4E 41 4C 20 46 41 4E 54 41 53 59 20 49 49   FINAL FANTASY II
7FD0  20 20 20 20 20 20 02 0A 03 01 C3 00 0F 7A F0 85         ......z..
7FF0  .. .. .. .. .. .. .. .. .. .. .. .. 00 80 .. ..   reset = $8000
```

- `$FFD5` = `$20`: LoROM, SlowROM. It looks like a padding space, but it's
  the map-mode byte.
- `$FFD6` = `$02`: RAM + battery.
- `$FFD7` = `$0A`: 1 MiB. `$FFD8` = `$03`: 8 KiB SRAM.
- `$FFD9` = `$01`: North America.
- Complement `$7A0F` + checksum `$85F0` = `$FFFF` ✓.
- Reset vector `$8000` = file `$0000`, which starts with bytes
  `78 18 FB C2 10 E2 20 9C 0D 42 9C 0B 42` = `SEI; CLC; XCE; REP #$10;
  SEP #$20; STZ $420D; STZ $420B`.

**Final Fantasy VI (US "FINAL FANTASY 3"), HiROM, unheadered.** File `$7FC0`
holds code bytes, so that candidate fails. File `$FFC0`:

```
FFC0  46 49 4E 41 4C 20 46 41 4E 54 41 53 59 20 33 20   FINAL FANTASY 3
FFD0  20 20 20 20 20 31 02 0C 03 01 33 00 CD A0 32 5F        1....3...2_
FFF0  .. .. .. .. .. .. .. .. .. .. .. .. 00 FF .. ..   reset = $FF00
```

- `$FFD5` = `$31`: HiROM + FastROM.
- `$FFD7` = `$0C`: 4 MiB declared for a 3 MiB ROM (rounded up).
- `$FFDA` = `$33`: an extended header is present.
- Complement `$A0CD` + checksum `$5F32` = `$FFFF` ✓.
- The reset stub at `$00:FF00` is `SEI; CLC; XCE; JML $C00019`. It jumps
  straight into the fast linear bank `$C0` (file `$000019`), where init sets
  `S=$15FF`, `D=$0000`, `DBR=$00` and writes `$420D` = 1.

---
Sources: SNESdev wiki "ROM header", "ROM file formats", "Memory map"
(Super Famicom Development Wiki mirror); bsnes `heuristics/super-famicom.cpp`
(field offsets, RAM sizes, region → video standard, header scoring);
Wikibooks "Super NES Programming/SNES memory map" (worked examples and copier
header layout only; its header table mislabels `$FFD9`).
