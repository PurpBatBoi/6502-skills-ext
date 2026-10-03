# NES / Famicom Memory Map (2A03 CPU view)

This covers the CPU's address space: RAM, the PPU and APU/IO register
windows, the cartridge area, and the vectors. As with the SNES file, the scope
is **the CPU and memory only**. PPU rendering and APU sound programming aren't
covered; the PPU registers get bit detail only where CPU code depends on
them (NMI, VRAM access, status polling). The 2A03 is a 6502 with **decimal
mode disabled** (see the 6502-instruction-set skill). Mapper banking is
cartridge-specific; to scaffold a project per mapper, use the
nes-llvm-mos-init skill.

## CPU memory map

| Address | Size | What |
|---------|------|------|
| `$0000-$07FF` | 2 KiB | Internal RAM |
| `$0800-$1FFF` | 6 KiB | Mirrors of `$0000-$07FF` (three times) |
| `$2000-$2007` | 8 | **PPU registers** |
| `$2008-$3FFF` | | Mirrors of `$2000-$2007`, repeating every 8 bytes |
| `$4000-$4017` | 24 | **APU and I/O registers** |
| `$4018-$401F` | 8 | APU/IO test-mode functions, normally disabled |
| `$4020-$FFFF` | | **Cartridge space**: unmapped by the console |
| ↳ `$6000-$7FFF` | 8 KiB | usually battery-backed save RAM or work RAM ("WRAM"/"PRG-RAM") |
| ↳ `$8000-$FFFF` | 32 KiB | usually PRG ROM, plus **mapper registers** (writes to "ROM" switch banks) |

Conventions inside the 2 KiB of RAM:
- `$0000-$00FF` is zero page.
- `$0100-$01FF` is the stack, which usually starts at `$01FF` and grows down.
- `$0200-$02FF` is most commonly the **OAM (sprite) buffer**, copied to the
  PPU each frame with `$4014` DMA.
- The rest is up to the game.

Cartridge rules that matter when reading code:
- The cartridge sees every CPU read and write, even outside `$4020-$FFFF`,
  except reads of `$4015`. So a mapper can react to writes anywhere.
- Readable cartridge memory should sit in `$4020-$FFFF`. A 2A03 decoding
  quirk can make DMA misbehave if the CPU is halted while reading
  `$4000-$401F`.
- Unmapped reads return **open bus**, which the cartridge hardware can affect.

**Vectors** (supplied by the cartridge, always at the top of the CPU space):

| Vector | Address | Typical use |
|--------|---------|-------------|
| NMI | `$FFFA-$FFFB` | V-blank (enabled by PPUCTRL bit 7) |
| RESET | `$FFFC-$FFFD` | power-on/reset init code |
| IRQ/BRK | `$FFFE-$FFFF` | mapper IRQ (e.g. scanline counters), APU IRQs, or `BRK` |

Unless the mapper fixes a bank at the top of the address space (e.g.
`$C000-$FFFF` always mapped to the last bank) or detects resets itself, the
vectors **and** a reset stub must exist in *every* bank. A bank can be
switched in at power-on.

**DPCM samples** play from `$C000-$FFF1` in practice: sample start addresses
run `$C000-$FFC0`, the longest sample is `$FF1` bytes, and playback wraps
from `$FFFF` to `$8000`.

## PPU registers (`$2000-$2007`, mirrored to `$3FFF`)

| Addr | Name | SDK (`<nes.h>`) | Access | Purpose |
|------|------|-----------------|--------|---------|
| `$2000` | PPUCTRL | `PPU.control` | W | NMI enable, VRAM increment, pattern tables, sprite size |
| `$2001` | PPUMASK | `PPU.mask` | W | rendering enables, left-column clipping, emphasis |
| `$2002` | PPUSTATUS | `PPU.status` | R | V-blank, sprite-0 hit, overflow; reading resets the write toggle |
| `$2003` | OAMADDR | `PPU.sprite.address` | W | OAM address |
| `$2004` | OAMDATA | `PPU.sprite.data` | R/W | OAM data |
| `$2005` | PPUSCROLL | `PPU.scroll` | W×2 | scroll X then Y (shares the write toggle) |
| `$2006` | PPUADDR | `PPU.vram.address` | W×2 | VRAM address, high byte then low |
| `$2007` | PPUDATA | `PPU.vram.data` | R/W | VRAM data; auto-increments the address |

**`$2000` PPUCTRL**
```
VPHBSINN
NN = base nametable (0-3: $2000/$2400/$2800/$2C00)
I  = VRAM increment per $2007 access: 0 = +1 (across), 1 = +32 (down)
S  = 8x8 sprite pattern table: 0 = $0000, 1 = $1000
B  = background pattern table: 0 = $0000, 1 = $1000
H  = sprite size: 0 = 8x8, 1 = 8x16
P  = EXT pin direction (leave 0)
V  = generate NMI at the start of V-blank
```
Turning V on *during* V-blank, while PPUSTATUS bit 7 is still set, fires an
NMI right away. Toggling it several times can fire several.

**`$2001` PPUMASK**
```
BGRsbMmG
G = grayscale
m = show background in the leftmost 8 pixels     M = show sprites in the leftmost 8 pixels
b = show background                               s = show sprites
R/G/B = color emphasis (on PAL, R and G are swapped)
```
With both `b` and `s` at 0 the screen is in **forced blank**, the only safe
time to access VRAM outside V-blank.

**`$2002` PPUSTATUS** (read-only)
```
VSO.....
V = in V-blank      S = sprite-0 hit      O = sprite overflow (buggy on hardware)
. = open bus (the PPU's last value)
```
Reading it **clears V** and resets the shared `$2005`/`$2006` write toggle.
The standard pattern is `BIT $2002` before writing `$2006` twice. Reading
exactly as V-blank starts can suppress that frame's flag and NMI, which is why
games wait for NMI instead of polling `$2002`.

**`$2007` PPUDATA reads are buffered.** A read returns the byte loaded by the
*previous* read, and then refills the buffer. So after setting `$2006`, the
first read is a throwaway. Palette reads (`$3F00+`) are the exception and
return immediately.

## APU and I/O registers (`$4000-$4017`)

| Addr | Name / SDK | Purpose |
|------|------------|---------|
| `$4000-$4003` | `APU.pulse[0]` | pulse channel 1 |
| `$4004-$4007` | `APU.pulse[1]` | pulse channel 2 |
| `$4008-$400B` | `APU.triangle` | triangle channel |
| `$400C-$400F` | `APU.noise` | noise channel |
| `$4010-$4013` | `APU.delta_mod` | DMC (sample) channel |
| `$4014` | OAMDMA / `SPRITE_DMA` | write `$XX` → copy CPU `$XX00-$XXFF` into OAM |
| `$4015` | status / `APU.status` | channel enables (write) / status (read) |
| `$4016` | `JOYPAD[0]` | write: controller strobe; read: controller 1 |
| `$4017` | `JOYPAD[1]` / `APU.fcontrol` | read: controller 2; write: APU frame counter |

**`$4014` OAMDMA:** writing page number `$XX` halts the CPU while it copies
256 bytes from `$XX00` (usually `$02` → `$0200`) to OAM, one read plus one
write per byte. That's 512 cycles plus 1-2 alignment cycles, so about
513-514 CPU cycles. It's normally done first thing in the NMI handler.

**`$4015`**
```
write: ---DNT21  enable DMC / noise / triangle / pulse 2 / pulse 1; also clears the DMC IRQ
read:  IF-DNT21  I = DMC IRQ, F = frame-counter IRQ, D = DMC still playing, N/T/2/1 = length counter > 0
                 reading clears the frame-counter IRQ flag; bit 5 is open bus
```

**`$4016` / `$4017` controllers**
- Write `$4016` bit 0 = 1 then 0 to latch both pads. The 1→0 strobe starts a
  new read.
- Each read of `$4016` (pad 1) or `$4017` (pad 2) returns the next button in
  bit 0. The order is **A, B, Select, Start, Up, Down, Left, Right**. After 8
  reads, official pads return 1.
- The other bits are open bus or expansion inputs, so mask with `AND #$01`.

**`$4017` write: APU frame counter**
```
MI------
M = sequencer mode: 0 = 4-step (can raise the frame IRQ), 1 = 5-step (never does)
I = inhibit the frame IRQ (setting it also clears a pending frame IRQ)
```
Reset code commonly writes `$40` here to stop the frame IRQ firing into an
unprepared IRQ vector.

## Classifying accesses when porting

| Address | Treat as |
|---------|----------|
| `$0000-$07FF` (and mirrors `$0800-$1FFF`) | RAM; normalize mirrors with `addr & $07FF` |
| `$0200-$02FF` (typical) | OAM shadow, *data* the NMI's `$4014` DMA ships to the PPU |
| `$2000-$2007` (+ mirrors to `$3FFF`) | PPU effects: `platform.h` calls, never memory. VRAM is reachable only through `$2006`/`$2007`. |
| `$4000-$4013`, `$4015`, `$4017` write | APU effects (sound) |
| `$4014` write | OAM DMA: a 256-byte copy to the PPU |
| `$4016`/`$4017` read | controller input |
| `$6000-$7FFF` | cartridge RAM, if the board has it |
| writes to `$8000-$FFFF` | **mapper register writes** (bank switches), not ROM stores |

---
Sources: NESdev wiki "CPU memory map" (user-supplied); llvm-mos SDK
`nes.h` (register layout and names); Mesen2 source (`NesPpu.cpp`,
`NesApu.cpp`, `ApuFrameCounter.h`, `NesController.h`) for every bit layout and
side effect above.
