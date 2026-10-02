---
name: 6502-memory-map
description: >-
  Memory maps, I/O registers, ROM entry points, and zero-page conventions for
  Apple II, Commodore 64, Atari 8-bit, and SNES (5A22 side). Covers
  Apple soft switches, language card, Monitor ROM, Applesoft FP; C64 banking,
  VIC-II/SID/CIA, KERNAL; Atari ANTIC/GTIA/POKEY, shadow registers, CIO/SIO;
  SNES bus A/B, LoROM/HiROM/ExHiROM, FastROM, $42xx CPU registers, $43xx
  DMA/HDMA, the ROM header ($FFC0, map mode, checksum) and .sfc/.smc files.
  Use this skill WHENEVER you need to know what an address, register or ROM
  routine means on these machines, where the screen/zero page/stack are, how
  banking works, or how a SNES ROM file is laid out. Trigger on addresses like $C050, $FDED, $D020, $FFD2, $D40A,
  $2118, $4200, $420B, $7E0000, $FFD5, on names like
  COUT/CHROUT/CIOV/POKEY/NMITIMEN/MDMAEN/HDMAEN/INIDISP, or on any "what is
  at address X" / "what does this STA do" / "is this ROM LoROM or HiROM"
  question. Pairs with the 6502-instruction-set, 6502-merlin-assembler,
  6502-sweet16, 6502-snes-sa1, and 6502-to-rust skills.
---

# Apple II, Commodore 64, Atari 8-bit & SNES Memory Maps

A 6502 program *is* its memory map: there are no system calls, just stores and
loads to magic addresses. To understand a routine you must know what each
address means on the target machine — a `STA $D020` is "set the C64 border
color", a `STA $C050` is "switch the Apple II to graphics", a `STA $D40A` is
"wait for horizontal blank on the Atari". The same address means different
things on different machines, so **identify the platform first.**

## Identify the platform

The C64 and Atari both map custom-chip registers around `$D000-$D7FF`, so
disambiguate by *which* registers and ROM calls appear:

| Clue | Platform |
|------|----------|
| `$C000`–`$C0FF` soft-switch stores/loads, `JSR $FDED`, `$0400` text screen, language card `$C08x` | Apple II |
| `STA $0001` banking, `JSR $FFD2`, `$D800` color RAM, `$D020`/`$D021` border/bg, SID at `$D400` | Commodore 64 |
| `JSR $E456`/`$E459` (CIOV/SIOV), `STA $D40A` (WSYNC), display list at `$D402`, POKEY `$D2xx`, page-2 shadow regs (`$022F`, `$0230`), page 6 `$0600` | Atari 8-bit |
| `JSR $F689` (SWEET16) | Apple II (Integer BASIC ROM) — see the sweet16 skill |
| 16-bit code, `REP`/`SEP`, toolbox calls | Apple IIgs — see 65816 notes in the 6502-instruction-set skill |
| 16-bit code + `STA $2100`/`$2118`, `$420B` DMA kicks, `$4200` NMI enable, `$7E`/`$7F` banks, long `JSL` | SNES — see `references/snes-memory.md` |
| SNES code touching `$2200-$23FF` or `$3000-$37FF` | SNES SA-1 cart — see the 6502-snes-sa1 skill |

The three 8-bit machines all put the stack at `$0100-$01FF` and use a precious
256-byte zero page, but almost everything else differs. On the SNES both are
relocatable within bank 0 (65816 `S` and `D` registers).

## How to read the references

Read only the file for the platform and topic at hand:

**Apple II**
- **`references/apple2-memory.md`** — full 64K layout, zero-page usage by
  DOS/ProDOS/Monitor/Applesoft, the `$C000-$C0FF` soft switches (video, keyboard,
  speaker, IIe aux-memory, game I/O), the `$C080-$C08F` language-card bank
  switching, text/lo-res/hi-res page addresses, and ROM sizes per model.
- **`references/apple2-rom-routines.md`** — Monitor ROM entry points (character
  I/O, screen, input, hex print) and the Applesoft floating-point package
  (FAC/ARG layout and FADD/FMULT/FDIV/FOUT/… entry points) plus Applesoft
  runtime zero-page (CHRGET, TXTPTR, the variable pointers).

**Commodore 64**
- **`references/c64-memory.md`** — the 6510 `$00/$01` processor port and the
  ROM/RAM/IO banking it controls, the full memory layout, and the VIC-II
  (`$D000`), SID (`$D400`), color RAM (`$D800`), CIA1 (`$DC00`) and CIA2
  (`$DD00`) register maps.
- **`references/c64-kernal.md`** — the KERNAL jump table (`$FF81-$FFF3`:
  CHROUT, CHRIN, GETIN, SETLFS, SETNAM, LOAD, SAVE, …), important KERNAL/BASIC
  zero-page locations, and BASIC ROM notes.

**Atari 400/800/XL/XE**
- **`references/atari8-memory.md`** — the memory layout, the GTIA (`$D000`),
  POKEY (`$D200`), PIA (`$D300`) and ANTIC (`$D400`) register maps, the
  display-list model, and the page-2 **shadow registers** the OS copies to
  hardware each frame.
- **`references/atari8-os.md`** — the `$E450` OS jump-vector table (CIOV, SIOV,
  SETVBV…), the CIO device-independent I/O system and IOCBs, SIO, and the
  (BCD) floating-point package at `$D800`.

**SNES / Super Famicom**
- **`references/snes-memory.md`** — the S-CPU's view of memory:
  - Bus A vs Bus B, the full bank map with Fast/Slow/XSlow access speeds,
    FastROM, and WRAM mirroring.
  - LoROM/HiROM/ExHiROM cart layouts, ROM-offset formulas, and where
    interrupt stubs must live.
  - A `$2100-$2183` PPU/APU register list (purpose only; no PPU bit detail).
  - Bit-level `$4200-$421F` CPU registers (NMI/IRQ, mul/div, joypad).
  - `$43xx` DMA/HDMA channels: how a transfer works and the HDMA table format.
  - Open bus.
- **`references/snes-rom-header.md`** — the cartridge header at `$00:FFC0`.
  Quick facts come first; read just those to locate the header or tell the
  layout. After that:
  - all fields, the map-mode/chipset/region codes, and the extended header;
  - ROM file formats and copier headers;
  - the checksum, with non-power-of-two mirroring;
  - layout-detection heuristics;
  - worked FF4 (LoROM) and FF6 (HiROM) examples.

  Read it for any question about a ROM file, its header, or its checksum.

## Why this matters for porting

When porting (see the 6502-to-rust skill), every access to one of these
addresses is an *external effect* that the intermediate language must model
explicitly: a hardware register read/write, a ROM service call, or a
documented OS variable. A plain RAM access becomes an array index; a `$D020`
write becomes "set border color"; a `JSR $FFD2` becomes "output character in A".
Mislabeling a hardware access as ordinary memory is the most common way a port
silently loses behavior. Use these references to classify every non-RAM address
the code touches.
