# SNES / Super Famicom Memory Map (5A22 S-CPU view)

This file covers the address space as the CPU sees it: the bus layout,
cartridge mapping, access speeds, the CPU's own control registers
(`$4200-$43FF`), and DMA/HDMA. The PPU and APU registers are listed by address
and purpose only, with no bit-level graphics or sound detail. For the
instruction set and the 5A22's CPU quirks, see `references/65816.md` in the
6502-instruction-set skill. For SA-1 carts, see the 6502-snes-sa1 skill. For
the ROM header and ROM files, see `snes-rom-header.md`.

Contents: Buses · Access speed · Memory map (+ cartridge layouts: LoROM,
HiROM, ExHiROM, ExLoROM, interrupt stubs) · Bus B registers `$21xx` · Old-style joypad
`$4016/7` · CPU registers `$4200-$421F` · DMA/HDMA `$43xx` (+ behavior) ·
Frame timing · Open bus · Classifying accesses when porting

## Buses

The SNES has **one 8-bit data bus and two address buses**:

- **Bus A** (24-bit): WRAM and the cartridge. Ordinary loads and stores go out
  here.
- **Bus B** (8-bit, "the SNES bus"): PPU1/PPU2 at `$2100-$213F`, the APU ports
  at `$2140-$217F`, and the WRAM data port at `$2180-$2183`. The CPU reaches it
  through the `$21xx` window in banks `$00-$3F`/`$80-$BF`.

"LoROM" and "HiROM" are not modes of the console. They describe how the
cartridge decodes the Bus A addresses it sees.

## Access speed

The master clock runs at ~21.477 MHz (NTSC; ~21.281 MHz PAL). An internal CPU
(IO) cycle always takes 6 master cycles. A memory access takes:

| Speed | Master cycles | Effective CPU rate |
|-------|---------------|--------------------|
| Fast  | 6  | ~3.58 MHz |
| Slow  | 8  | ~2.68 MHz |
| XSlow ("Ultraslow") | 12 | ~1.79 MHz |

**FastROM** means `MEMSEL` (`$420D`) bit 0 = 1. It makes ROM accesses in banks
`$80-$FF` Fast. The same ROM read through banks `$00-$7D` is always Slow, which
is why FastROM games run their code from `$80-$BF` / `$C0-$FF`.

## Memory map

| Banks | Addresses | Speed | What responds |
|-------|-----------|-------|---------------|
| `$00-$3F` | `$0000-$1FFF` | Slow | WRAM, mirror of `$7E:0000-$1FFF` (the "low RAM" every bank shares) |
| | `$2000-$20FF` | Fast | Bus A (unused / cart) |
| | `$2100-$21FF` | Fast | **Bus B**: PPU, APU ports, WRAM port |
| | `$2200-$3FFF` | Fast | Bus A (cart; e.g. SA-1 registers `$2200-$23FF`, SA-1 I-RAM `$3000-$37FF`) |
| | `$4000-$41FF` | XSlow | CPU: old-style joypad `$4016/$4017` |
| | `$4200-$43FF` | Fast | CPU: control, mul/div, DMA registers |
| | `$4400-$5FFF` | Fast | Bus A (cart) |
| | `$6000-$7FFF` | Slow | "Expansion" area, Bus A (cart; HiROM SRAM, SA-1 BW-RAM window) |
| | `$8000-$FFFF` | Slow | Cartridge ROM |
| `$40-$7D` | `$0000-$FFFF` | Slow | Cartridge |
| `$7E-$7F` | `$0000-$FFFF` | Slow | **WRAM**, 128 KB (`$7E:0000` – `$7F:FFFF`) |
| `$80-$BF` | (same as `$00-$3F`) | (same) | Mirror of `$00-$3F`, but `$8000-$FFFF` is Fast when FastROM is on |
| `$C0-$FF` | `$0000-$FFFF` | Fast if FastROM, else Slow | Cartridge |

Useful consequences:

- With `DBR` = `$00-$3F` or `$80-$BF`, plain `abs` addressing reaches low WRAM,
  the hardware registers and ROM. In banks `$40-$7F` and `$C0-$FF` there are no
  registers, so code that sets `DBR=$7E` must use long addressing
  (`STA $002100` / `STA.l`) to reach hardware.
- WRAM `$7E:0000-$1FFF` is the same RAM as `$00:0000-$1FFF`. Direct page and
  the stack (always bank 0) live there.
- The `$4016/$4017` region is XSlow. Everything at `$4200+` is Fast.
- The space left for the cartridge holds at most 12 MiB − 128 KiB of ROM:
  - the upper halves of `$00-$3F`/`$80-$BF`;
  - all of `$40-$7D`;
  - all of `$C0-$FF`.

  The standard maps below use 4 MiB (LoROM, HiROM) or about 8 MiB (ExHiROM,
  and the unofficial ExLoROM).

### Cartridge layouts (Bus A decoding)

The layouts come from bsnes's board database and match the SNESdev wiki
(ExLoROM: bsnes, corroborated by nesdev forum posts).
"Mode 20/21/25" is shorthand for the map-mode byte at `$00:FFD5`; `+$10` in
that byte means FastROM (`$30`, `$31`, `$35`).

| Layout | Max | ROM in CPU space | ROM file offset | Battery SRAM (typical) |
|--------|-----|------------------|-----------------|------------------------|
| **LoROM** (`$20`) | 4 MiB | `$00-$7D`,`$80-$FF`:`$8000-$FFFF`, 32 KiB per bank; cart A15 not connected | `(bank & $7F) × $8000 + (addr & $7FFF)` | `$70-$7D`,`$F0-$FF`:`$0000-$7FFF` |
| **HiROM** (`$21`) | 4 MiB | `$40-$7D`,`$C0-$FF`:`$0000-$FFFF` (64 KiB banks, linear); upper halves also at `$00-$3F`,`$80-$BF`:`$8000-$FFFF` | `(bank & $3F) × $10000 + addr` | `$20-$3F`,`$A0-$BF`:`$6000-$7FFF` |
| **ExHiROM** (`$25`) | 8 MiB − 64 KiB | `$C0-$FF` (+ `$80-$BF` upper halves) = first 4 MiB; `$40-$7D` (+ `$00-$3F` upper halves) = second 4 MiB; cart A22 = SNES A23 inverted | `$C0`+: `(bank & $3F) × $10000 + addr`; `$40-$7D`: `$400000 + (bank & $3F) × $10000 + addr` | `$A0-$BF`:`$6000-$7FFF` (bsnes also maps `$20-$3F`; the wiki shows `$80-$BF`) |
| *ExLoROM* (unofficial; header still says `$20`/`$30`) | ~8 MiB − 64 KiB | `$80-$FF`:`$8000-$FFFF` = first 4 MiB; `$00-$7D`:`$8000-$FFFF` = second part (≤ ~3.9 MiB); only A15 ignored | `$80`+: `(bank & $7F) × $8000 + (addr & $7FFF)`; `$00-$7D`: `$400000 + bank × $8000 + (addr & $7FFF)` | `$70-$7D`,`$F0-$FF`:`$0000-$7FFF` |

**LoROM:**
- Banks `$00-$7D` are the same ROM as `$80-$FD`. Banks `$7E`/`$7F` are WRAM,
  so in a full 4 MiB ROM the last 64 KiB can only be reached at `$FE-$FF`.
- Registers and low RAM appear only in `$00-$3F`/`$80-$BF`, which hold the
  first 2 MiB of ROM. So code goes early in the ROM and bulk data late: code
  running from `$40+` can't reach hardware with plain 16-bit addresses.
- The lower halves of `$40-$7D`/`$C0-$FF` mirror the upper halves only where
  no SRAM is mapped. SRAM placement varies by board, and it's often mirrored
  at `$F0-$FF`.

**HiROM:**
- HiROM works as a superset of LoROM. Code can live in the `$8000-$FFFF`
  halves of `$00-$3F`/`$80-$BF`, next to the registers, while data uses the
  64 KiB banks at `$C0-$FF`, which have half as many bank boundaries.
- `$40-$7D` mirrors `$C0-$FD`, with minor board variations.
- SRAM placement is board-dependent: some boards decode only part of
  `$20-$3F`.

**ExHiROM:**
- The file holds the `$C0-$FF` half first, then the `$40-$7D` half. ROM file
  offset `$400000+` is the second half.
- Bank `$00`, and with it the header and vectors, comes from the **second**
  half. FastROM code (`$80-$FF`) runs from the first half.
- Only two commercial games use it: Tales of Phantasia and Daikaijū
  Monogatari 2, both on two-ROM "LJ3x" boards.

**ExLoROM:**
- Nintendo never defined this layout, so it has no map-mode code; it exists
  only in ROM hacks (SnesLab: "very rare unofficial"). It extends LoROM the
  way ExHiROM extends HiROM, and is strictly inferior to mode `$25`.
- As in ExHiROM, bank `$00`, and with it the header and vectors, comes from
  the second part, at file `$400000+`. Emulator support is inconsistent.
- Terminology: "ExtLoROM"/"ExtHiROM" are the same things under another name.
- "BigLoROM" (fullsnes), meaning LoROM games over 2 MiB such as Super
  Metroid, is plain mode `$20`.
- Prefer "mode `$20`/`$21`/`$25`" over copier-era names. Even the official
  modes vary slightly from board to board.

**Interrupt stubs (all layouts):**
- Vectors are 16-bit and the CPU forces bank `$00`, so every reset and
  interrupt entry point must sit in `$00:8000-$FFFF`. In the ROM file that is
  `$0000-$7FFF` (LoROM), `$8000-$FFFF` (HiROM), `$408000-$40FFFF`
  (ExHiROM) or `$400000-$407FFF` (ExLoROM).
- FastROM games keep a short stub there and `JML` into a `$80+` bank. For
  example, FF6's reset handler is `SEI; CLC; XCE; JML $C00019`.

The **ROM header** is always at CPU `$00:FFC0-$FFDF`, with the optional
extended header at `$FFB0-$FFBF` and the vectors at `$FFE0-$FFFF`. Its file
offset depends on the layout. For field layouts, map-mode and chipset codes,
the checksum, copier headers, and how to detect the layout of a ROM file, see
**`snes-rom-header.md`**.

## Bus B registers (`$2100-$2183`) — address / purpose only

"Write-twice" registers take two consecutive 8-bit writes (low then high, or
two halves of a value). Most PPU registers can only be written safely during
forced blank or V-blank. Scroll, window and color-math registers can also be
written during H-blank, which is what HDMA is for.

| Address | Name | Purpose |
|---------|------|---------|
| `$2100` | INIDISP | forced blank (bit 7) + master brightness |
| `$2101` | OBSEL | sprite size and sprite graphics base |
| `$2102-$2104` | OAMADDL/H, OAMDATA | sprite table (OAM) address + write port |
| `$2105` | BGMODE | BG mode 0-7, tile size |
| `$2106` | MOSAIC | mosaic size / enable |
| `$2107-$210A` | BG1SC-BG4SC | BG tilemap address and size |
| `$210B-$210C` | BG12NBA, BG34NBA | BG tile graphics address |
| `$210D-$2114` | BGnHOFS/BGnVOFS | BG scroll (write-twice); `$210D/E` also Mode 7 scroll |
| `$2115` | VMAIN | VRAM address increment mode |
| `$2116-$2117` | VMADDL/H | VRAM word address |
| `$2118-$2119` | VMDATAL/H | VRAM write port (usual DMA target) |
| `$211A` | M7SEL | Mode 7 settings |
| `$211B-$2120` | M7A-M7D, M7X, M7Y | Mode 7 matrix and center (write-twice); `$211B/$211C` also feed the `$2134-6` signed multiply |
| `$2121-$2122` | CGADD, CGDATA | palette (CGRAM) address + write port (write-twice) |
| `$2123-$212B` | W12SEL…WOBJLOG | window masks, positions, logic |
| `$212C-$212F` | TM, TS, TMW, TSW | main/sub screen layer enables, window enables |
| `$2130-$2132` | CGWSEL, CGADSUB, COLDATA | color math |
| `$2133` | SETINI | interlace, overscan (bit 2), pseudo-hires, EXTBG |
| `$2134-$2136` | MPYL/M/H | read: signed 24-bit product of the 16-bit `$211B` value × the last byte written to `$211C`; no wait needed, but not usable during Mode 7 rendering |
| `$2137` | SLHV | read: latch H/V counters (only if `$4201` bit 7 = 1) |
| `$2138` | OAMDATAREAD | OAM read port |
| `$2139-$213A` | VMDATALREAD/H | VRAM read port |
| `$213B` | CGDATAREAD | palette read port |
| `$213C-$213D` | OPHCT, OPVCT | latched H/V counter (read twice) |
| `$213E-$213F` | STAT77, STAT78 | PPU status / version; `$213F` bit 7 = interlace field |
| `$2140-$2143` | APUIO0-3 | SPC700 mailbox ports, mirrored to `$217F`. A write goes to the SPC700; a read returns what the SPC700 wrote. They are separate latches, so you don't read back your own write. |
| `$2180` | WMDATA | WRAM read/write port, auto-increments the address |
| `$2181-$2183` | WMADDL/M/H | 17-bit WRAM address for `$2180` (write-only; reads are open bus) |

## Old-style joypad (`$4016-$4017`, XSlow)

- `$4016` write bit 0 = latch both controller ports. Reads return port 1
  Data1 in bit 0 and Data2 in bit 1.
- `$4017` read returns port 2 Data1/Data2 in bits 0-1. Bits 2-4 read as 1.
- Normal pads shift out B, Y, Select, Start, Up, Down, Left, Right, A, X, L, R,
  then four 0 bits, then 1s. Don't touch these registers while auto-joypad read
  is running.

## CPU registers `$4200-$421F` (bit level)

`$4200-$420D` are write-only and `$4210-$421F` are read-only. Reading a
write-only register returns open bus.

**`$4200` NMITIMEN** — interrupt enables (`$00` on reset)

```
n-yx---a
n  = 1: NMI at the start of V-blank (V=$E1, or $F0 with overscan)
yx = 00: no timer IRQ
     01: H-IRQ every scanline when H = HTIME
     10: V-IRQ once per frame when V = VTIME (at H≈0)
     11: HV-IRQ when V = VTIME and H = HTIME
a  = 1: auto-joypad read every V-blank into $4218-$421F
```

**`$4201` WRIO** — programmable output port. Bit 7 goes to controller port 2
pin 6 and the PPU latch: a 1→0 transition latches the H/V counters like
reading `$2137`. Bit 6 goes to port 1 pin 6. It powers up as `$FF`.

**`$4202` WRMPYA / `$4203` WRMPYB** — writing `$4203` starts an **unsigned 8×8**
multiply. The 16-bit product is in `$4216/7` after **8 CPU cycles**. `$4202` is
kept, so you can rewrite `$4203` to multiply again.

**`$4204/5` WRDIV (dividend, 16-bit) / `$4206` WRDIVB (divisor)** — writing
`$4206` starts an **unsigned 16÷8** divide. After **16 CPU cycles** the
quotient is in `$4214/5` and the remainder in `$4216/7`. Divide by 0 gives
quotient `$FFFF` and remainder = dividend.

**`$4207/8` HTIME, `$4209/A` VTIME** — 9-bit timer IRQ compare values. H counts
0-339 and V counts 0-261 (NTSC) or 0-311 (PAL). Out-of-range values never
fire.

**`$420B` MDMAEN** — writing bit *n* = 1 starts general DMA on channel *n*. The
CPU is halted until every selected channel finishes, lowest channel first.

**`$420C` HDMAEN** — bit *n* = 1 enables HDMA on channel *n*. The setting
persists from frame to frame. Writing 0 pauses the channel.

**`$420D` MEMSEL** — bit 0 = FastROM: 6-cycle access to `$80-$BF:8000-FFFF` and
`$C0-$FF`.

**`$4210` RDNMI** — bit 7 = NMI flag. It is set at the start of V-blank and
cleared when read or at the end of V-blank. It is independent of `$4200`
bit 7. NMI handlers conventionally read it to clear the flag. Bits 3-0 are the
5A22 version; bits 6-4 are open bus.

**`$4211` TIMEUP** — bit 7 = IRQ flag. **Reading it releases the IRQ line**, so
an H/V-IRQ handler must read `$4211`, or the IRQ fires again right after `RTI`.

**`$4212` HVBJOY** — bit 7 = in V-blank, bit 6 = in H-blank, bit 0 =
auto-joypad read in progress. Poll bit 0 until it clears before reading
`$4218-$421F`.

**`$4213` RDIO** — input side of the `$4201` port.

**`$4214/5` RDDIV** — quotient. **`$4216/7` RDMPY** — product or remainder.

**`$4218-$421F` JOY1-JOY4** — auto-joypad results: `JOY1` = port 1, `JOY2` =
port 2, and `JOY3`/`JOY4` = the Data2 lines of ports 1/2 (multitap). Read as
a 16-bit word from the low address:

```
bit  15 14 13     12    11 10 9 8 | 7 6 5 4 | 3-0
     B  Y  Select Start Up Dn L R | A X L R | 0
```

## DMA / HDMA registers (`$43x0-$43xF`, x = channel 0-7)

All are readable and writable. They power up as `$FF` and are unchanged on
reset.

| Address | Name | DMA meaning | HDMA meaning |
|---------|------|-------------|--------------|
| `$43x0` | DMAPx | control (below) | control (below) |
| `$43x1` | BBADx | Bus B register: `$21xx` | same |
| `$43x2-4` | A1TxL/H, A1Bx | Bus A address (24-bit) | HDMA table start |
| `$43x5-6` | DASxL/H | byte count; **0 = 65536** | indirect address (low 16 bits) |
| `$43x7` | DASBx | — | indirect-data bank |
| `$43x8-9` | A2AxL/H | — | current table address |
| `$43xA` | NLTRx | — | line counter + repeat flag |
| `$43xB`/`$43xF` | — | unused byte (the two addresses are the same register) | same |

**`$43x0` DMAPx:**

```
da-ifttt
d   = direction: 0 = A-bus → B-bus (CPU memory → PPU), 1 = B → A
a   = HDMA only: 0 = direct (table holds data), 1 = indirect (table holds pointers)
i   = DMA only: 0 = increment A address, 1 = decrement
f   = DMA only: 1 = fixed A address (e.g. fill from one byte)
ttt = transfer unit, B-bus addresses written per unit:
      000 p            (1 byte)
      001 p, p+1       (2)       e.g. VRAM $2118/$2119
      010 p, p         (2)       e.g. write-twice registers
      011 p, p, p+1, p+1  (4)
      100 p, p+1, p+2, p+3  (4)
      101 p, p+1, p, p+1  (4)
      110 = 010, 111 = 011
```

### DMA behavior

- Write the channel registers, then write `$420B`. The CPU gets one more cycle,
  then halts until the transfer ends.
- Cost: **8 master cycles per byte**, regardless of FastROM. Each channel adds
  8 cycles of overhead, and the whole transfer adds about 12-24 more for
  setup and realignment.
- The A-bus address increments (or decrements) its low 16 bits only. **The bank
  byte never changes**, so a DMA wraps within its bank.
- DMA uses Bus A and Bus B at the same time. Consequences:
  - An A-bus address pointing at `$21xx`, `$4300-$437F`, `$420B` or `$420C`
    reads open bus or has no effect. Bus B registers can't be reached
    through A.
  - WRAM to WRAM through `$2180` fails, because both sides would be WRAM.
- After the transfer the count `$43x5/6` is 0, unless HDMA cut it short.
- HDMA takes priority. HDMA pauses an active DMA, and if HDMA needs the same
  channel, it terminates that DMA.

### HDMA behavior

- At the start of each frame (V=0), each enabled channel copies `$43x2/3` into
  `$43x8/9` and loads its first line-count byte. Indirect channels also load
  the first pointer. The CPU pauses for this.
- On each visible scanline, at H-blank, a channel writes **one transfer unit**
  (1, 2 or 4 bytes per `ttt`) to `$21xx`. Overhead is about 18 master cycles
  per line, plus 8 per active channel, plus 16 when an indirect address is
  loaded, plus 8 per byte.
- **Table format:** a series of entries. Each starts with a `$43xA` byte:
  - bit 7 = repeat, bits 6-0 = line count.
  - Repeat = 0: one unit of data follows, which is written once, and then the
    channel waits *count* lines.
  - Repeat = 1: *count* units follow, written one per line.
  - A count byte of `$00` ends the channel for this frame. (Indirect tables
    hold 2-byte pointers in place of the data.)
- The counter is decremented before it is tested, so `$80` means "128 lines,
  no repeat", not "0 lines with repeat".
- HDMA doesn't run during V-blank. It restarts automatically next frame as long
  as the `$420C` bit stays set.
- Starting HDMA mid-frame needs `$43x8-A` (and `$43x5/6` for indirect) set by
  hand. A channel that already ended this frame can't be restarted.

## Frame timing the CPU cares about

- One scanline is 1364 master cycles. There are 262 lines per frame on NTSC
  and 312 on PAL.
- V-blank starts at line `$E1` (225), or `$F0` (240) when overscan
  (`$2133` bit 2) is on. NMI fires there if enabled.
- Every scanline the CPU pauses for 40 master cycles of WRAM refresh, about
  536 cycles into the line.
- Auto-joypad read starts early in V-blank and takes 4224 master cycles
  (about 3 scanlines). `$4212` bit 0 is set while it runs.

## Open bus

Reading an address nothing drives returns the last value seen on the data bus.
The CPU keeps that value in its memory data register (MDR). For a plain
`LDA $xxxx` it is normally the last operand byte fetched, the high byte of the
address. Internal CPU cycles don't change it. Unused bits of readable
registers (e.g. `$4210` bits 6-4, `$4211` bits 6-0) are open bus too, so mask
them. The PPUs keep their own open-bus latches for unmapped bits in
`$2134-$213F`.

## Classifying accesses when porting

| Address | Treat as |
|---------|----------|
| `$7E:0000-$7F:FFFF`, `$00-$3F/$80-$BF:$0000-$1FFF` | RAM (WRAM; low 8 KB shared) |
| `$21xx` | PPU / APU / WRAM-port side effects. VRAM, OAM and CGRAM are not CPU-addressable; they only change through these ports. |
| `$4016/7`, `$4200-$421F` | input, interrupts, mul/div hardware |
| `$420B` write | a whole block copy (`$43xx` describes it) — model it as a memcpy to a port |
| `$43xx` | DMA/HDMA configuration; HDMA = per-scanline register writes |
| cart ROM / SRAM | per the cartridge layout above |

---
Sources: Anomie's SNES memory map, register, timing and DMA docs (the
Super Famicom Development Wiki); bsnes (`sfc/cpu/io.cpp`, board database,
header heuristics) for `$420D`, H-blank timing, cart layouts and map-mode
bytes.
