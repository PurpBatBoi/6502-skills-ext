# SA-1 Register Reference (`$2200-$230E`)

The registers are mapped in banks `$00-$3F`/`$80-$BF`. `$2200-$22FF` are
**write-only** and `$2300-$23FF` are **read-only**. Each register belongs to
one side:

- **S** = written/read by the S-CPU (SNES)
- **C** = written/read by the SA-1
- **Both** = either CPU may write it

A write from the wrong CPU is ignored. A read of a write-only register, or of
the other side's read register, returns open bus. The "Init" column gives the
power-on value.

Contents: [Control & interrupts](#control--interrupts) ·
[Timer](#timer) · [Memory mapping & protection](#memory-mapping--protection) ·
[DMA](#dma) · [Bitmap / character conversion](#bitmap--character-conversion) ·
[Arithmetic](#arithmetic) · [Variable-length bit](#variable-length-bit) ·
[Read registers](#read-registers)

## Summary

| Addr | Name | Side | Purpose |
|------|------|------|---------|
| `$2200` | CCNT | S | SA-1 control: IRQ/NMI to SA-1, wait, reset, message |
| `$2201` | SIE | S | S-CPU interrupt enable |
| `$2202` | SIC | S | S-CPU interrupt clear |
| `$2203-4` | CRV | S | SA-1 reset vector |
| `$2205-6` | CNV | S | SA-1 NMI vector |
| `$2207-8` | CIV | S | SA-1 IRQ vector |
| `$2209` | SCNT | C | S-CPU control: IRQ to S-CPU, vector overrides, message |
| `$220A` | CIE | C | SA-1 interrupt enable |
| `$220B` | CIC | C | SA-1 interrupt clear |
| `$220C-D` | SNV | C | S-CPU NMI vector override |
| `$220E-F` | SIV | C | S-CPU IRQ vector override |
| `$2210` | TMC | C | H/V timer control |
| `$2211` | CTR | C | timer restart |
| `$2212-3` | HCNT | C | timer H compare |
| `$2214-5` | VCNT | C | timer V compare |
| `$2220-3` | CXB-FXB | S | Super MMC ROM banks |
| `$2224` | BMAPS | S | S-CPU BW-RAM window block |
| `$2225` | BMAP | C | SA-1 BW-RAM window block |
| `$2226` | SBWE | S | S-CPU BW-RAM write enable |
| `$2227` | CBWE | C | SA-1 BW-RAM write enable |
| `$2228` | BWPA | S | BW-RAM protected-area size |
| `$2229` | SIWP | S | S-CPU I-RAM write enable per page |
| `$222A` | CIWP | C | SA-1 I-RAM write enable per page |
| `$2230` | DCNT | C | DMA control |
| `$2231` | CDMA | Both | character-conversion DMA parameters |
| `$2232-4` | SDA | Both | DMA source address |
| `$2235-7` | DDA | Both | DMA destination address (write starts DMA) |
| `$2238-9` | DTC | C | DMA byte count |
| `$223F` | BBF | C | BW-RAM bitmap format |
| `$2240-F` | BRF | C | bitmap register file (char-conv type 2) |
| `$2250` | MCNT | C | arithmetic control |
| `$2251-2` | MA | C | multiplicand / dividend |
| `$2253-4` | MB | C | multiplier / divisor (write `$2254` = start) |
| `$2258` | VBD | C | variable-length bit control |
| `$2259-B` | VDA | C | variable-length bit ROM address |
| `$2300` | SFR | S read | S-CPU flags + message from SA-1 |
| `$2301` | CFR | C read | SA-1 flags + message from S-CPU |
| `$2302-3` | HCR | C read | timer H count |
| `$2304-5` | VCR | C read | timer V count |
| `$2306-A` | MR | C read | arithmetic result (40-bit) |
| `$230B` | OF | C read | arithmetic overflow |
| `$230C-D` | VDP | C read | variable-length data port |
| `$230E` | VC | — | "version code": open bus on real hardware |

## Control & interrupts

**`$2200` CCNT** (S, init `$20`)

```
IWRNmmmm
I    = 1: raise IRQ to SA-1 (sets CFR bit 7)
W    = 1: SA-1 waits (halts); 0: run
R    = 1: SA-1 held in reset; 1→0 transition starts it at CRV, bank $00
N    = 1: raise NMI to SA-1 (sets CFR bit 4)
mmmm = message to SA-1 (read in CFR bits 3-0)
```

The SA-1 runs only while W = 0 and R = 0. Power-on `$20` = held in reset.

**`$2201` SIE** (S, init `$00`) — `I-C-----`. Bit 7 enables the IRQ from the
SA-1 (`SCNT` bit 7). Bit 5 enables the character-conversion DMA IRQ. Enabling
a source whose flag is already set raises the IRQ at once.

**`$2202` SIC** (S) — `I-C-----`. Writing 1 to bit 7 or 5 clears that S-CPU
IRQ flag. The S-CPU's IRQ line drops once both flags are clear.

**`$2203/4` CRV, `$2205/6` CNV, `$2207/8` CIV** (S) — the SA-1's reset, NMI
and IRQ vectors (16-bit, bank `$00`). The SA-1 takes these from the registers,
never from ROM.

**`$2209` SCNT** (C, init `$00`)

```
IV-Nmmmm
I    = 1: raise IRQ to S-CPU (sets SFR bit 7)
V    = 1: S-CPU IRQ vector ($00:FFEE/F) reads SIV instead of ROM
N    = 1: S-CPU NMI vector ($00:FFEA/B) reads SNV instead of ROM
mmmm = message to S-CPU (read in SFR bits 3-0)
```

**`$220A` CIE** (C, init `$00`) — `ITDN----`. Each bit enables one SA-1
interrupt source:
- bit 7: IRQ from the S-CPU;
- bit 6: timer IRQ;
- bit 5: SA-1 DMA-end IRQ;
- bit 4: NMI from the S-CPU.

All IRQ sources vector through `CIV`; NMI goes through `CNV`.

**`$220B` CIC** (C) — `ITDN----`. Writing 1 clears the matching flag in `CFR`.

**`$220C/D` SNV, `$220E/F` SIV** (C) — replacement S-CPU native-mode NMI/IRQ
vectors, used while `SCNT` bit 4 / bit 6 is set.

## Timer

**`$2210` TMC** (C, init `$00`)

```
T-----VH
T = 0: H/V mode (counts like the PPU: H 0-340, V 0-261 NTSC / 0-311 PAL)
    1: linear mode (one free-running 18-bit counter: H = low 9 bits, V = high 9 bits)
V = enable V compare    H = enable H compare
   H only: IRQ every line when H = HCNT
   V only: IRQ when V = VCNT (at H = 0)
   both:   IRQ at (HCNT, VCNT)
```

**`$2211` CTR** (C) — any write resets the counter to 0.

**`$2212/3` HCNT, `$2214/5` VCNT** (C) — 9-bit compare values (bit 8 in the
high byte). The SnesLab register notes repeat `$2212/3` under "Set V-Count";
the V registers are `$2214/5`.

## Memory mapping & protection

**`$2220-$2223` CXB / DXB / EXB / FXB** (S, init `$00`/`$01`/`$02`/`$03`)

```
P----bbb
bbb = 1 MB ROM block (0-7)
P   = 1: the LoROM region below also uses bbb; 0: it stays at its fixed block
```

| Reg | HiROM region | LoROM region (P=1) | Fixed block (P=0) |
|-----|--------------|--------------------|-------------------|
| CXB | `$C0-$CF` | `$00-$1F:8000-FFFF` | 0 |
| DXB | `$D0-$DF` | `$20-$3F:8000-FFFF` | 1 |
| EXB | `$E0-$EF` | `$80-$9F:8000-FFFF` | 2 |
| FXB | `$F0-$FF` | `$A0-$BF:8000-FFFF` | 3 |

LoROM regions show 32 KB per bank, like a LoROM cart. HiROM regions show 64 KB
per bank. The mapping applies to the S-CPU, the SA-1, SA-1 DMA, and the
variable-length bit reader. The maximum is 8 MB. (Snes9x ≤1.53 treated P as
always 1. bsnes 0.7x didn't apply MMC to the variable-length reader.)

**`$2224` BMAPS** (S, init `$00`) — `---bbbbb`: which 8 KB block of BW-RAM
(0-31) appears at the S-CPU's `$00-$3F`/`$80-$BF`:`$6000-$7FFF`.

**`$2225` BMAP** (C, init `$00`)

```
Sbbbbbbb
S = 0: SA-1's $6000-$7FFF window shows linear BW-RAM, block = b4-b0 (32 × 8 KB)
    1: window shows the $60-$6F bitmap view, block = b6-b0 (128 × 8 KB of pixels)
```

**`$2226` SBWE** (S, init `$00`) / **`$2227` CBWE** (C, init `$00`) —
`W-------`. W = 1 enables BW-RAM writes. Protection applies only to the `BWPA`
area, and only while **both** W bits are 0. Either W bit unlocks the area for
both CPUs.

**`$2228` BWPA** (S, init `$0F`) — `----nnnn`: the protected area is BW-RAM
`$40:0000` up to `$40:0000 + (256 << n) - 1`. With n = 0 that's
`$40:0000-$40:00FF`. Power-on `$0F` covers all of BW-RAM. (The formula line in
the SnesLab notes contradicts its own example; `256 << n` matches the example
and bsnes.)

**`$2229` SIWP** (S, init `$00`) — bit *n* = **1 allows** S-CPU writes to I-RAM
`$3n00-$3nFF`. Power-on `$00` = all pages protected.

**`$222A` CIWP** (C, init `$00`) — bit *n* = **1 allows** SA-1 writes to I-RAM
page *n*, which the SA-1 sees at both `$3n00` and `$0n00`. bsnes also clears
it when the SA-1 leaves reset.

> Polarity note: the SnesLab register notes say 1 = "enable protection" for
> SIWP/CIWP. bsnes (`IRAM::writeCPU`/`writeSA1`) drops the write when the bit
> is **0**, which matches 1 = write-enable. Follow bsnes.

## DMA

**`$2230` DCNT** (C, init `$00`)

```
EPMT-Dss
E  = 1: DMA enabled
P  = priority: 0 = SA-1 CPU, 1 = DMA
M  = 0: normal DMA      1: character-conversion DMA
T  = char-conv type: 0 = type 2 (SA-1 writes BRF), 1 = type 1 (BW-RAM bitmap → S-CPU DMA)
D  = normal-DMA destination: 0 = I-RAM, 1 = BW-RAM
ss = normal-DMA source: 00 = ROM, 01 = BW-RAM, 10 = I-RAM
```

Normal DMA works for **ROM→I-RAM, ROM→BW-RAM, BW-RAM→I-RAM, and I-RAM→BW-RAM**.
Same-memory copies aren't supported. To run one:

1. Set `DCNT`, `SDA` and `DTC`.
2. Write `DDA` low byte first. The DMA starts on the write to **`$2236`** when
   the destination is I-RAM, or on the write to **`$2237`** when it is BW-RAM.
3. At the end, `CFR` bit 5 (DMA IRQ) is set; it interrupts the SA-1 if `CIE`
   bit 5 is on.

**`$2231` CDMA** (Both, init `$00`)

```
E--sssbb
E   = 1: end character-conversion type 1 (written by the S-CPU when its DMA is done)
sss = virtual VRAM width in characters = 2^sss (0-5 → 1…32)
bb  = color depth: 00 = 8 bpp, 01 = 4 bpp, 10 = 2 bpp
```

**`$2232-4` SDA** (Both) — 24-bit source address, written low → high.
**`$2235-7` DDA** (Both) — 24-bit destination; the trigger bytes are given
above. **`$2238/9` DTC** (C) — byte count.

## Bitmap / character conversion

**`$223F` BBF** (C, init `$00`) — `F-------`. F = 0: the `$60-$6F` bitmap view
is 4 bpp (each byte address = one nibble). F = 1: 2 bpp.

**`$2240-$224F` BRF** (C) — two 8-pixel buffers: `$2240-7` and `$2248-F`.
With char-conv **type 2** enabled (`DCNT` = E, M set, T clear), writing
`$2247` or `$224F` converts that row of 8 pixels into planar tile data in
I-RAM.

**Type 1 flow:**

1. The SA-1 sets `DCNT` (E, M, T set).
2. Set `CDMA`, `SDA` (= the BW-RAM bitmap) and `DDA` (= the I-RAM buffer).
   The write to `$2236` starts the conversion and raises the S-CPU
   character-DMA IRQ (`SFR` bit 5, delivered if `SIE` bit 5 is on).
3. The S-CPU runs its own DMA from that BW-RAM address to VRAM (`$2118`). The
   SA-1 hardware supplies converted tiles in place of the raw bytes.
4. The S-CPU writes `CDMA` bit 7 = 1 to end the conversion.

## Arithmetic

**`$2250` MCNT** (C, init `$00`)

```
------AD
A D
0 0 = multiply          signed MA × signed MB → MR $2306-$2309 (32-bit signed)
0 1 = divide            signed MA ÷ unsigned MB → quotient $2306-7 (signed), remainder $2308-9 (unsigned)
1 x = cumulative sum    MR += signed MA × signed MB, 40-bit signed in $2306-$230A
Writing MCNT with A = 1 clears MR to 0.
```

**`$2251/2` MA, `$2253/4` MB** (C). **Writing `$2254` (MB high byte) runs the
operation.** Write `MA`, then `MB` low, then `MB` high.

- After a multiply or sum, **MB is cleared and MA kept**. Repeated sums only
  need a new MB (and MA when it changes).
- After a divide, **both MA and MB are cleared**.
- Division rounds toward negative infinity, so the remainder is always
  0 ≤ r < MB. Divide-by-zero yields MR = 0 (bsnes; undocumented).

**`$230B` OF** (C read) — bit 7 = the cumulative sum overflowed 40 bits.

## Variable-length bit

**`$2259-$225B` VDA** (C) — 24-bit ROM address of the bit stream. Writing
`$225B` (bank byte) resets the bit position to 0, so write it last.

**`$2258` VBD** (C)

```
H---llll
H    = 0: fixed mode — each write to VBD advances the position by llll bits
       1: auto mode — each read of $230D advances it by llll bits
llll = field length in bits (0 means 16)
```

In fixed mode the write *consumes* a field. Read `VDP`, use the low `llll`
bits, then write `VBD` with that length to step past them. This is what the
SnesLab note means by "length of previously stored data".

**`$230C/D` VDP** (C read) — the 16 bits starting at the current bit position,
LSB-first. Read `$230C` then `$230D`. In auto mode, the `$230D` read is the
one that advances.

## Read registers

**`$2300` SFR** (S read)

```
IVDNmmmm
I    = IRQ from SA-1 pending (SCNT bit 7)
V    = S-CPU IRQ vector currently from SIV
D    = character-conversion DMA IRQ pending
N    = S-CPU NMI vector currently from SNV
mmmm = message from SA-1 (SCNT bits 3-0)
```

**`$2301` CFR** (C read)

```
ITDNmmmm
I    = IRQ from S-CPU pending      T = timer IRQ pending
D    = DMA-end IRQ pending          N = NMI from S-CPU pending
mmmm = message from S-CPU (CCNT bits 3-0)
```

**`$2302/3` HCR, `$2304/5` VCR** (C read) — timer counters. **Reading `$2302`
latches both**, so read `$2302` first.

**`$2306-$230A` MR** — see Arithmetic. **`$230B` OF** — see Arithmetic.
**`$230C/D` VDP** — see Variable-length bit.

**`$230E` VC** — documented by Nintendo as a version code. On real carts it
reads as open bus, so don't rely on it.

---
Sources: SnesLab SA-1 article and "SA-1 Registers" notes; bsnes
`sfc/coprocessor/sa1/{io,memory,iram,bwram,rom,dma,sa1}.cpp` for every bit
layout, trigger and power-on value above.
