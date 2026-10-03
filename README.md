# 6502 Skills

A cluster of Claude skills for working with **6502-family assembly** — reading,
writing, understanding, and porting it — with a focus on the Apple II/IIgs
(Merlin assembler), the SNES (65C816 / Ricoh 5A22, plus the SA-1 coprocessor),
the Commodore 64, the Atari 400/800/XL/XE, and the NES. All skills share a `6502-`
prefix so they group together once installed.

SNES coverage is the CPU and the memory map only: the 5A22 core and its CPU
registers, DMA/HDMA, cartridge mapping, and the SA-1. PPU graphics and APU
sound programming are out of scope, and the PPU/APU registers are listed by
address and purpose only.

## The skills

| Skill | What it covers |
|-------|----------------|
| **`6502-instruction-set`** | NMOS 6502 / 65C02 / 65816 mnemonics, addressing modes, opcode bytes, cycle counts, and exact flag semantics. 65816 bank-boundary wrapping. CPU-variant notes (6510/C64, 2A03/NES, 5A22/SNES). The reference for *what an instruction does*. |
| **`6502-merlin-assembler`** | Merlin macro-assembler source: column layout, directives (DFB/DW/DDB/DCI/ASC/HEX/LUP/MAC…), macros and parameters, label/variable conventions, and Merlin's left-to-right expression evaluation. Apple Merlin 8/16/32 and Commodore Merlin 64/128. |
| **`6502-memory-map`** | Apple II, C64, Atari 8-bit, NES, and SNES memory maps, I/O registers, ROM entry points, and zero-page conventions: Apple soft switches, language card, Monitor ROM, Applesoft FP; C64 6510 banking, VIC-II/SID/CIA, the KERNAL jump table; Atari ANTIC/GTIA/POKEY, shadow registers, CIO/SIO, the $E450 vectors; NES PPU/APU/IO registers, OAM DMA, controllers, cart space; SNES bus A/B, LoROM/HiROM, FastROM speeds, `$4200` CPU registers, `$43xx` DMA/HDMA. |
| **`6502-snes-sa1`** | The SA-1 SNES coprocessor (a second 65C816 in the cart): dual-CPU model and per-side memory maps, boot, inter-CPU IRQ/messages, I-RAM/BW-RAM write protection, Super MMC banking, SA-1 and character-conversion DMA, the arithmetic unit, variable-length bit reads, the timer, and every `$2200-$230E` register. |
| **`6502-sweet16`** | Wozniak's SWEET16 — the 16-bit interpreted pseudo-processor in the Apple II Integer BASIC ROM (entry `$F689`): registers, opcode set, invocation, and how to decode its inline bytecode. |
| **`6502-to-c`** | The same lift → raise → emit workflow targeting portable C99, NMOS 6502 only (6510/C64, 2A03/NES). One C core builds as host C and back onto the 6502 with llvm-mos (C64, Atari 8-bit, Apple II, NES). Covers C's integer-promotion traps, a `platform.h` hardware layer, `__zp`, inline asm for ROM calls, and differential testing on host and `mos-sim` via the bundled `scripts/run-tests.sh`. |
| **`6502-to-rust`** | A two-stage workflow for porting 6502 assembly to idiomatic Rust via an explicit, flag-faithful intermediate language: lift → recover intent → emit, plus correctness rules and a verification method. |

## Installing

Each skill is a directory with a `SKILL.md`, following the [Agent Skills](https://agentskills.io)
open standard, so the same files work across Claude Code, opencode, Kilo Code,
Codex, and any other tool that implements it. You point your agent at the skill
directories; what differs per agent is *which* directory it scans.

### Quick install — `install.sh`

`install.sh` symlinks (or copies) the seven `6502-*` skills into the right place:

```sh
./install.sh --claude            # Claude Code, personal      → ~/.claude/skills/
./install.sh --agents            # open standard (opencode/Kilo/Codex) → ~/.agents/skills/
./install.sh --claude --agents   # both at once
./install.sh --opencode --kilo   # each agent's own global dir
./install.sh --to PATH           # any explicit directory, e.g. a project's .claude/skills
./install.sh --agents --copy     # copy instead of symlink (Windows, or to vendor into a repo)
```

Symlink is the default, so editing a skill here updates every install. `--help`
lists all options. After installing, restart the agent; in Claude Code run
`/skills` to confirm they loaded.

### Where each agent looks

| Agent | Global (all projects) | Per project |
|-------|-----------------------|-------------|
| **Claude Code** | `~/.claude/skills/<name>/` | `<project>/.claude/skills/<name>/` |
| **opencode** | `~/.agents/skills/`, `~/.config/opencode/skills/`, `~/.claude/skills/` | `.agents/skills/`, `.opencode/skills/`, `.claude/skills/` |
| **Kilo Code** | `~/.agents/skills/`, `~/.kilo/skills/`, `~/.claude/skills/` | `.agents/skills/`, `.kilo/skills/`, `.claude/skills/` |
| **Codex** | `~/.agents/skills/` | `.agents/skills/` (cwd up to repo root) |

`.agents/skills/` is the common open-standard location read by opencode, Kilo,
and Codex; `.claude/skills/` is Claude Code's. To make the skills available in a
specific project rather than globally, install into that project's `.agents/skills/`
or `.claude/skills/` with `install.sh --to PATH`.

### Manual install

Without the script, copy or symlink each `6502-*` directory into one of the
locations above. For Claude Code, personal install:

```sh
for s in 6502-*/; do ln -s "$PWD/${s%/}" ~/.claude/skills/; done
```

The packaged `.skill` bundles (gitignored) are the zip form for skill
marketplaces; for direct use, install the directories as above.

## How they fit together

```
            6502-instruction-set   ← semantics of every instruction
                     │
 6502-merlin-assembler   6502-memory-map   6502-sweet16
   (source dialect)      (what addresses     (the inline VM)
                          mean per platform)
                                │
                          6502-snes-sa1      ← SNES SA-1 carts: second CPU,
                                │              its own map and registers
         6502-to-rust   6502-to-c   ← use all of the above to port
                       (C99: host + llvm-mos)
```

When porting (`6502-to-rust` or `6502-to-c`), the other skills supply the context the port
depends on:
- the instruction set fixes semantics;
- the memory map classifies every address as RAM / hardware / ROM call;
- the SA-1 skill adds the second CPU's address space on SA-1 carts;
- the Merlin skill decodes the source;
- SWEET16 handles any inline-bytecode regions.

## Layout

Each skill is a directory with a `SKILL.md` (the always-loaded instructions and
trigger description) and a `references/` folder of detail files loaded only when
needed (progressive disclosure). `6502-to-c` also ships `scripts/run-tests.sh`.
See each `SKILL.md` for the reference index.

## Authoring

Built and iterated with the `skill-creator` skill. Key technical facts
(SWEET16 encodings, Merlin directives, ROM routine addresses, C64 hardware maps)
were verified against primary sources (Wozniak's BYTE 1977 SWEET16 article, the
Brutal Deluxe Merlin 32 manual, the Apple II/C64 memory-map references) during
authoring.

The `6502-to-c` skill's C code and llvm-mos details were verified by building
and running them. The test machine had gcc 16 (MinGW) and llvm-mos clang 24
(SDK in `C:\llvm-mos`). Every snippet passes both on the host and on `mos-sim`
(16-bit `int`). The drivers, predefined macros, `__zp`, inline-asm
constraints, calling convention, and soft-stack behavior were read from the
compiler's own output.

The 65816/SNES/SA-1 content was checked against these sources:

| Source | Used for |
|--------|----------|
| [WDC W65C816S datasheet](https://www.westerndesigncenter.com/wdc/documentation/w65c816s.pdf) (§3, §7 caveats, vector tables) | bank-boundary wrapping, vectors, emulation-mode stack/direct-page rules |
| [Apple IIgs Hardware Reference, 2nd ed.](https://archive.org/details/Apple_IIGS_Hardware_Reference_1988_Adn-Wesley_Publishing_second_edition) | the Apple side of the comparison |
| Super Famicom Development Wiki — [Memory Mapping](https://wiki.superfamicom.org/memory-mapping), [Timing](https://wiki.superfamicom.org/timing), [Registers](https://wiki.superfamicom.org/registers), [DMA & HDMA](https://wiki.superfamicom.org/dma-and-hdma), Open Bus, Instruction Wrapping (Anomie's docs) | SNES bus/map, speeds, CPU registers, DMA/HDMA, wrapping tests |
| [SnesLab: 65c816](https://sneslab.net/wiki/65c816), [SnesLab: SA-1](https://sneslab.net/wiki/SA-1) and SA-1 register notes | 5A22/SA-1 overview, SA-1 register map |
| SNESdev wiki — [Memory map](https://snes.nesdev.org/wiki/Memory_map), [ROM header](https://snes.nesdev.org/wiki/ROM_header), [ROM file formats](https://snes.nesdev.org/wiki/ROM_file_formats), [CPU vectors](https://snes.nesdev.org/wiki/CPU_vectors) | LoROM/HiROM/ExHiROM layouts, header fields, chipset/region codes, checksum, copier headers, vector table |
| nesdev forums — [CPU→Cart Address Mapping for ExLoROM/ExHiROM](https://forums.nesdev.org/viewtopic.php?t=14808), [ExtHiROM And ExtLoROM?](https://forums.nesdev.org/viewtopic.php?t=22704); [SnesLab: ExLoROM](https://sneslab.net/wiki/ExLoROM) | ExLoROM layout and status, ExHiROM commercial games, map-mode terminology (corroborates bsnes `EXLOROM` board) |
| [Wikibooks: Super NES Programming/SNES memory map](https://en.wikibooks.org/wiki/Super_NES_Programming/SNES_memory_map) | secondary only: FF4/FF6 header examples (bytes re-verified), copier-header layout |
| [bsnes](https://github.com/bsnes-emu/bsnes) source (`sfc/cpu`, `sfc/coprocessor/sa1`, `processor/wdc65816`, board database, `heuristics/super-famicom.cpp`) | tie-breaker wherever the docs disagreed; header offsets, region → NTSC/PAL, header scoring |

Where the sources conflicted, the skills follow the datasheet or bsnes. The
conflicts were:
- `$420D` FastROM is bit 0, not bit 1;
- overscan is `$2133` bit 2, not bit 3;
- SA-1 `SIWP`/`CIWP` 1 = write-enable;
- `BWPA` size is `256 << n`, and it applies only when both write-enables are 0;
- `CBWE` is SA-1-owned;
- VCNT is at `$2214/5`;
- the `(a,X)` pointer is fetched from the program bank, not bank 0;
- `$FFD9` is the region and `$FFDA` the developer ID (Wikibooks swaps them);
- an interrupt clears PBR only, not DBR, and `XCE` changes neither
  (datasheet §7.11; Wikibooks claims otherwise);
- the NTSC region codes are `$00`, `$01`, `$0B`, `$0D`, `$0F`, `$10` (bsnes),
  wider than the wiki's "`$00`/`$01` only";
- ExHiROM SRAM placement is board-dependent (bsnes `$20-$3F`/`$A0-$BF`, the
  wiki shows `$80-$BF`).