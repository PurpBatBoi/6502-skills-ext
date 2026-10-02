---
name: 6502-snes-sa1
description: >-
  The Nintendo SA-1 (RF5A123) SNES cartridge coprocessor: a second 65C816
  running at 10.74 MHz alongside the SNES CPU. Covers the dual-CPU model
  (S-CPU vs SA-1 "C-CPU"), each side's memory map, booting the SA-1,
  inter-CPU IRQ/NMI and message passing, I-RAM and BW-RAM with their
  write-protection traps, Super MMC ROM banking (up to 8 MB), SA-1 DMA and
  character-conversion DMA, the signed multiply/divide/cumulative-sum unit,
  variable-length bit reads, the H/V timer, and the $2200-$23FF register set at
  bit level. Use this skill WHENEVER code or a question involves the SA-1:
  registers $2200-$23FF (CCNT, SCNT, SIE, CIE, CXB-FXB, BMAPS, SIWP, DCNT,
  MCNT, VBD…), I-RAM at $3000-$37FF, BW-RAM at $40-$4F or the $6000-$7FFF
  window, map mode $23, "SA-1 Root"/"SA-1 Pack" ROM hacks, SA-1 games like
  Super Mario RPG or Kirby Super Star, or an SNES routine that writes $2200 or
  waits on another CPU. Pairs with the 6502-instruction-set (65816 semantics)
  and 6502-memory-map (base SNES memory map) skills.
---

# SNES SA-1 Coprocessor

The SA-1 is a full **65C816 core inside the cartridge**, clocked at 10.74 MHz:
four times the 2.68 MHz the SNES CPU gets on SlowROM. It uses the same
instruction set, flags and modes, so the 6502-instruction-set skill applies
unchanged. What's different is the **machine around it**: a second address
space, shared memories with protection switches, and a register block both
CPUs use to talk to each other.

Naming: the SNES CPU is the **S-CPU** and the SA-1's CPU is the **C-CPU**.
Neither is master. Each can interrupt the other, but the SA-1 powers up held
in reset, and only the S-CPU can release it.

## Identify SA-1 code

| Clue | Meaning |
|------|---------|
| Header map-mode byte `$00:FFD5` = `$23` (or `$33`) | SA-1 cartridge |
| Header chipset `$00:FFD6` = `$3x` (e.g. `$34` RAM, `$35` RAM + battery) | SA-1 cartridge. BW-RAM size is in `$FFD8`, and `$FFBD` should be `$00`. See `snes-rom-header.md` in the 6502-memory-map skill. |
| Writes to `$2200`-`$222A`, reads of `$2300`/`$2301` | SA-1 register traffic |
| Data at `$3000-$37FF` in banks `$00-$3F`/`$80-$BF` | I-RAM (shared fast RAM) |
| Banks `$40-$4F`, or `$6000-$7FFF` windows | BW-RAM (save RAM / work RAM) |
| Same routine reads `$2301` / writes `$2209` | runs **on the SA-1** |
| Same routine writes `$2200` / reads `$2300` | runs **on the S-CPU** |

**Work out which CPU a routine runs on first.** The two CPUs see different
memory at the same address (see below), and each register is writable from
only one side. Reading an SA-1 routine as if it ran on the S-CPU is the
classic misread.

## Memory maps — one cart, two views

| Range | S-CPU sees | SA-1 sees |
|-------|-----------|-----------|
| `$00-$3F`,`$80-$BF`:`$0000-$07FF` | WRAM (low 8 KB mirror) | **I-RAM** (same 2 KB as `$3000-$37FF`) |
| `$00-$3F`,`$80-$BF`:`$0800-$1FFF` | WRAM | open bus |
| `$00-$3F`,`$80-$BF`:`$2100-$21FF`, `$4000-$43FF` | PPU/APU, CPU and DMA registers | **open bus**: no PPU, no SNES DMA |
| `$00-$3F`,`$80-$BF`:`$2200-$23FF` | SA-1 registers (S-CPU subset) | SA-1 registers (SA-1 subset) |
| `$00-$3F`,`$80-$BF`:`$3000-$37FF` | I-RAM | I-RAM |
| `$00-$3F`,`$80-$BF`:`$6000-$7FFF` | 8 KB BW-RAM block chosen by `BMAPS` `$2224` | 8 KB block chosen by `BMAP` `$2225` (linear or bitmap view) |
| `$00-$3F`,`$80-$BF`:`$8000-$FFFF` | ROM, LoROM-style, via Super MMC | same ROM |
| `$40-$4F` | BW-RAM, linear (≤256 KB, mirrored) | BW-RAM, linear |
| `$60-$6F` | open bus | BW-RAM **bitmap view**: one byte per 2- or 4-bit pixel (`BBF` `$223F`) |
| `$7E-$7F` | WRAM | open bus |
| `$C0-$FF` | ROM, HiROM-style 1 MB blocks, via Super MMC | same ROM |

What follows from that:

- **The SA-1 cannot touch WRAM, VRAM, the PPU, the APU, or SNES DMA.** Data
  it produces has to go into I-RAM or BW-RAM, and the S-CPU then moves it on
  (usually by DMA from BW-RAM/I-RAM to `$2118`). This is the main design
  constraint of every SA-1 program.
- On the SA-1, **direct page and the stack (bank 0, `$0000-$07FF`) are I-RAM**.
  A routine moved from the S-CPU that keeps variables in `$0000-$1FFF` WRAM
  breaks on the SA-1 unless its addresses are remapped. SA-1 Pack–style hacks
  do exactly this remapping, typically moving low RAM to I-RAM `$3000` and
  WRAM tables to BW-RAM.
- Speeds: the SA-1 reads ROM and I-RAM in 1 cycle at 10.74 MHz, and BW-RAM in
  2 cycles (5.37 MHz). It loses extra cycles whenever the S-CPU is using the
  same memory at the same moment (a **bus conflict**), so SA-1 timing is
  never exact while both CPUs share ROM, BW-RAM or I-RAM.

## Boot sequence (S-CPU side)

The SA-1 powers up with `CCNT` (`$2200`) = `$20`: held in **reset**. It sleeps
while bit 5 (reset) or bit 6 (wait) is set.

```
; S-CPU, before starting the SA-1
LDA #$FF : STA $2229      ; SIWP: let S-CPU write all of I-RAM (powers up $00 = all protected!)
LDA #$80 : STA $2226      ; SBWE: S-CPU may write BW-RAM
REP #$20
LDA #sa1_reset : STA $2203 ; CRV: SA-1 reset vector (bank $00)
LDA #sa1_nmi   : STA $2205 ; CNV
LDA #sa1_irq   : STA $2207 ; CIV
SEP #$20
STZ $2200                 ; CCNT: clear reset bit → SA-1 starts at CRV, PB=$00
```

When reset is released, the SA-1 starts at `CRV` in bank `$00`. Its own
interrupts **always** go through the `CNV`/`CIV` registers, never the ROM
vector table. Inside its init code the SA-1 normally sets `CIWP` (`$222A`) to
`$FF` and `CBWE` (`$2227`) to `$80`. Both power up as write-protected. bsnes
also clears `CIWP` to 0 whenever the SA-1 is released from reset, so set it
after every restart.

## Talking between CPUs

Each direction has a **4-bit message**, an **IRQ** bit, and an enable/clear
pair:

| Direction | Send | Receiver reads | Receiver enables | Receiver clears |
|-----------|------|----------------|------------------|-----------------|
| S-CPU → SA-1 IRQ | `CCNT` `$2200` bit 7 (+ message bits 3-0) | `CFR` `$2301` bit 7, message bits 3-0 | `CIE` `$220A` bit 7 | `CIC` `$220B` bit 7 |
| S-CPU → SA-1 NMI | `CCNT` bit 4 | `CFR` bit 4 | `CIE` bit 4 | `CIC` bit 4 |
| SA-1 → S-CPU IRQ | `SCNT` `$2209` bit 7 (+ message bits 3-0) | `SFR` `$2300` bit 7, message bits 3-0 | `SIE` `$2201` bit 7 | `SIC` `$2202` bit 7 |

There are also internal IRQ sources. The SA-1 timer and SA-1 DMA-end interrupt
the SA-1 through `CIV` (`CIE`/`CIC`/`CFR` bits 6 and 5). Character-conversion
DMA interrupts the S-CPU (`SIE`/`SIC`/`SFR` bit 5).

`SCNT` bits 6 and 4 let the SA-1 **override the S-CPU's native IRQ/NMI
vectors**. While set, S-CPU reads of `$00:FFEE/F` (IRQ) and `$00:FFEA/B` (NMI)
return `SIV` (`$220E`) and `SNV` (`$220C`) in place of ROM.

Many games and SA-1 Pack–style hacks skip interrupts and **poll a shared
mailbox**:

1. The S-CPU writes a routine pointer and arguments into I-RAM.
2. It writes `CCNT` with IRQ = 1 to wake the SA-1.
3. It spins on an I-RAM flag (or on `SFR`) until the SA-1 signals done.

While it waits, the S-CPU only has WRAM and registers to itself, which is fine
because the SA-1 can't use those anyway.

## Write protection — the usual "my writes vanish" bug

| Memory | S-CPU writes allowed when | SA-1 writes allowed when |
|--------|---------------------------|--------------------------|
| I-RAM page `$3n00-$3nFF` (n = 0-7) | `SIWP` `$2229` bit n = **1** | `CIWP` `$222A` bit n = **1** |
| BW-RAM inside the `BWPA` area | `SBWE` `$2226` bit 7 = 1 **or** `CBWE` `$2227` bit 7 = 1 | same |
| BW-RAM outside the `BWPA` area | always | always |

Both I-RAM registers **power up as `$00`, which protects every page**. Bit = 1
means *write enabled*. (The SnesLab register notes print this polarity
backwards; bsnes, which runs commercial SA-1 games correctly, uses 1 =
enabled.)

BW-RAM protection is narrower than it looks:
- `BWPA` (`$2228`, bits 3-0 = n) protects the first `256 << n` bytes of BW-RAM.
- That area is protected only while **both** `SBWE` and `CBWE` are 0. Setting
  either enable bit unlocks it for both CPUs. Kirby's Dream Land 3 depends on
  this.
- `BWPA` powers up as `$0F`, which covers all of BW-RAM, so until a game sets
  `SBWE` or `CBWE`, every BW-RAM write is dropped.

## Super MMC — ROM banking (up to 8 MB)

`CXB`/`DXB`/`EXB`/`FXB` (`$2220-$2223`): bits 2-0 pick which **1 MB block** of
ROM appears in each region. Bit 7 decides whether the LoROM banks follow it.

| Register | HiROM region (always follows) | LoROM region if bit 7 = 1 (else fixed MB) | Power-on |
|----------|-------------------------------|-------------------------------------------|----------|
| `CXB` `$2220` | `$C0-$CF` | `$00-$1F`:`$8000-$FFFF` (else MB 0) | `$00` |
| `DXB` `$2221` | `$D0-$DF` | `$20-$3F`:`$8000-$FFFF` (else MB 1) | `$01` |
| `EXB` `$2222` | `$E0-$EF` | `$80-$9F`:`$8000-$FFFF` (else MB 2) | `$02` |
| `FXB` `$2223` | `$F0-$FF` | `$A0-$BF`:`$8000-$FFFF` (else MB 3) | `$03` |

Both CPUs (and SA-1 DMA and the variable-length bit reader) see the same
mapping. The power-on values `{0,1,2,3}` give a plain 4 MB layout. Writing
`{4,5,6,7}` with bit 7 clear keeps the first 4 MB in the LoROM banks and puts
the last 4 MB at `$C0-$FF`, so all 8 MB are visible at once. Writing
`{$80,$81,$80,$81}` imitates a standard 2 MB LoROM with FastROM mirrors.

## Other hardware (details in the register reference)

- **SA-1 DMA** (`DCNT` `$2230`, `SDA`/`DDA`/`DTC`): byte copies ROM → I-RAM,
  ROM → BW-RAM, BW-RAM → I-RAM, or I-RAM → BW-RAM. Writing the destination
  address byte that fires it starts the copy: `$2236` for an I-RAM
  destination, `$2237` for BW-RAM. When it ends, it raises the SA-1 DMA IRQ
  flag.
- **Character-conversion DMA** turns a linear bitmap into SNES planar tiles in
  I-RAM:
  - *Type 1*: the S-CPU's own DMA reads from BW-RAM, and the SA-1 converts
    the data on the fly. It interrupts the S-CPU when it's ready, and the
    S-CPU ends it with `CDMA` bit 7.
  - *Type 2*: the SA-1 writes pixel rows into the bitmap register file
    `$2240-$224F`. Each write to `$2247`/`$224F` converts one row.
- **Arithmetic unit** (`MCNT` `$2250`):
  - signed 16×16 multiply, signed÷unsigned 16-bit divide, or a 40-bit signed
    multiply-accumulate;
  - writing `$2254` (high byte of `MB`) starts the operation;
  - results appear at `$2306-$230A`.
- **Variable-length bit reader** (`VBD` `$2258`, `VDA` `$2259-B`): streams 1-16
  bit fields out of ROM through `$230C/D`. It is meant for decompression.
- **H/V timer** (`TMC` `$2210`): an IRQ to the SA-1 at an H and/or V count
  (PPU-style), or a free-running 18-bit linear counter. It does not depend on
  the PPU.

## How to read the reference

- **`references/registers.md`** — every SA-1 register from `$2200` to `$230E`:
  - which CPU may write or read it, bit layout, and power-on value;
  - the exact arithmetic semantics (signedness, what gets cleared, rounding);
  - how each DMA mode is triggered;
  - the variable-length bit stepping rules.

  Read it whenever you decode a write to `$22xx` or a read of `$23xx`.

## Porting / tracing checklist

1. Tag every routine **S-CPU** or **SA-1**. Use the clues table above, and
   follow the CRV/CNV/CIV values to find the SA-1 entry points.
2. Resolve each address against the right CPU's map. `$0000-$07FF` and
   `$6000-$7FFF` mean different memory on each side.
3. Treat the CPU handoff (`$2200` write, then polling I-RAM/`SFR`) as a
   **synchronization point** between two threads. Don't treat it as a
   function call.
4. Model `$2251-$2254` / `$2306-$230B` as a math call, and model `$2236`/`$2237`
   writes as memcpy calls.
5. Check the protection registers before concluding that a store "does
   nothing".

---
Sources: SnesLab SA-1 article and register notes, cross-checked
against bsnes `sfc/coprocessor/sa1/*` and its SA-1 board map. Where they
disagree (I-RAM protection polarity, BWPA size/rule, `$2227` owner, V-count
address) this skill follows bsnes.
