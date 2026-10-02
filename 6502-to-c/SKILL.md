---
name: 6502-to-c
description: >-
  A workflow for porting NMOS 6502 assembly (6502, 6510/C64, 2A03/NES; Apple
  II, Commodore 64, Atari 8-bit, NES, Merlin source) to portable C99 by first
  lifting it to an explicit, flag-faithful intermediate language and then
  raising that to idiomatic C. One C core builds two ways: as host C (PC
  tools, tests) and back onto the 6502 with llvm-mos
  (mos-c64-clang, mos-apple2-clang, mos-atari8-*, mos-nes-*). Covers C's
  integer-promotion traps (uint8_t wrap, ~m, 16-bit int on llvm-mos), carry,
  overflow and BCD, idioms (16-bit math, multiply, pointer loops, jump
  tables), a platform.h layer for hardware/ROM calls, zero page (__zp), inline
  asm for ROM routines, and differential testing on host and mos-sim. Use this
  skill WHENEVER the user wants to port, translate, convert, decompile, or
  rewrite 6502 assembly in C, asks how a 6502 routine looks in C, or wants
  assembly turned into llvm-mos C. Not for 65C02/65816 code. Pairs with the
  6502-instruction-set, 6502-memory-map, 6502-merlin-assembler, and
  6502-sweet16 skills.
---

# Porting 6502 Assembly to C99 via an Intermediate Language

This is the same method as the 6502-to-rust skill, with C as the target: **lift
to a faithful IL, raise the IL to intent, then emit C.** Going straight to C
in one step usually fails, either as an unreadable transliteration or as a
"clean" port that silently loses carry, wraparound and decimal-mode behavior.
C makes the second failure *worse* than Rust does: its integer promotion
rules compile wrong arithmetic without a single warning by default.

```
6502 asm ──lift──▶ IL (flag-faithful) ──raise──▶ portable C99 core
                                                  ├─ host:     platform.h → functions/mocks + faithful oracle
                                                  └─ llvm-mos: platform.h → volatile MMIO / ROM calls on the real 6502
```

One core, two backends. The core is ordinary C99 that never touches an
address directly. `platform.h` is the only file that knows whether it's
running on a PC or on a C64, Atari, Apple II or NES.

**Scope:** NMOS 6502 code, plus the 6510 (C64) and 2A03 (NES, decimal mode
disabled), including undocumented opcodes. 65C02 and 65816 code is out of
scope.

## Prerequisites — gather these first

1. **CPU:** 6502, 6510, or 2A03. Decimal mode is real on the first two and a
   no-op on the 2A03. See the 6502-instruction-set skill.
2. **Platform:** classify every address as RAM, hardware register, or
   ROM/OS call with the 6502-memory-map skill. That classification decides
   what goes into `platform.h`.
3. **Assembler dialect:** for Merlin source, expand macros and re-bracket
   expressions first (6502-merlin-assembler). Port SWEET16 regions with the
   6502-sweet16 skill.
4. **Decimal mode:** any `ADC`/`SBC` between `SED` and `CLD` is BCD.
5. **Target:** host only, llvm-mos only, or both. Usually both: develop and
   test on the host, then ship on the 6502.

## The workflow

### Stage 1 — Lift to IL

Translate each instruction into IL with every register, flag and memory
access explicit. Don't simplify yet. `references/il-spec.md` has the grammar,
the per-instruction table, the flag helpers, undocumented opcodes, and the
loop trip-count rules: a `DEX/BNE` loop runs 256 times when started at 0, but
`INY/CPY/BCC` runs once.

### Stage 2 — Raise the IL

- **Flag liveness:** delete flag writes that nothing reads. That removes about
  80% of the noise. Only drop a flag you've proven dead.
- **Idioms:** byte-pair math becomes `uint16_t`, shift-add loops become `*`/`/`,
  `(zp),Y` walks become array loops, copy and fill loops become
  `memcpy`/`memset` (watch for overlap), jump tables become `switch`, and BCD
  stays BCD.
- **Types:** byte pairs used together become `uint16_t`, and buffers become
  arrays/pointers.

### Stage 3 — Emit C99

`references/c-patterns.md` has the trap table, the helpers, the faithful
oracle, the idiom catalog with tested C, the `platform.h` pattern, and
verification. Two output shapes:

- **Idiomatic C** (the default): real functions and types, explicit wrap
  casts, and no flags left over.
- **Faithful `struct cpu`** (host only): one function per instruction,
  provably equal to the original. It's the test oracle, and the fallback for
  self-modifying code.

For the 6502 build, `references/llvm-mos.md` covers drivers, the 16-bit
`int`, costs, `__zp`, hardware headers per platform, inline asm for ROM calls,
the calling convention for leftover `.s` files, and testing on `mos-sim`.

## C rules that are easy to get wrong

1. **`uint8_t` arithmetic happens in `int`.** Cast every result back:
   `a = (uint8_t)(a + 1u)`. Compile with `-Wconversion` so the compiler finds
   the casts you missed.
2. **`~m` is an `int`.** `SBC` must be `adc8(a, (uint8_t)~m, c)`, or the carry
   is wrong.
3. **Addresses wrap at 16 bits and zero page wraps at 8.** Write
   `mem[(uint16_t)(addr + 1u)]` and `mem[(uint8_t)(zp + x)]`.
4. **llvm-mos `int` is 16-bit.** `hi << 8` on a promoted byte is undefined
   behavior there; write `(uint16_t)hi << 8`. On the host, `uint16_t * uint16_t`
   can overflow signed `int`; write `(uint32_t)a * b`.
5. **Carry is inverted on subtract.** After `CMP`, C = `reg >= m`. Port compares
   as `<`/`>=`, not as replayed subtraction.
6. **A forward copy with overlapping regions is a fill.** Don't replace it
   with `memcpy` (undefined behavior) or `memmove` (a different result).
7. **Decimal mode changes `ADC`/`SBC` completely.** Port with
   `bcd_add`/`bcd_sub`. The NES never uses it.
8. **Hardware and ROM accesses are effects, not memory.** They go through
   `platform.h`. On the 6502 side they're `volatile`; reads count too.
9. **Self-modifying code and computed jumps:** recover the intent (an index
   or a `switch`). Otherwise use the oracle on the host, or keep the region as
   a `.s` file on llvm-mos.

## Worked micro-example

```
        CLC
        LDA $06
        ADC $08
        STA $0A
        LDA $07
        ADC $09
        STA $0B
```
Lift, prove the final carry dead, recognize a 16-bit add:
```c
static uint16_t rd16(const uint8_t *p)       { return (uint16_t)(p[0] | ((uint16_t)p[1] << 8)); }
static void     wr16(uint8_t *p, uint16_t v) { p[0] = (uint8_t)v; p[1] = (uint8_t)(v >> 8); }

wr16(&zp[0x0A], (uint16_t)(rd16(&zp[0x06]) + rd16(&zp[0x08])));   /* word[$0A] = word[$06] + word[$08] */
```
This builds unchanged for the host and for llvm-mos. Mark `zp` with `__zp` on
the 6502 build if it really is zero page. If the carry out of the high byte
were live, the function would return it, computed from a `uint32_t` sum.

## Verify

Run a differential test: the faithful oracle against the idiomatic port, on
exhaustive byte inputs and boundary cases. Run it on the host with
`-Wall -Wextra -Wpedantic -Wconversion` and the undefined-behavior checks;
MinGW needs `-fsanitize-undefined-trap-on-error`. Then run the same tests on
`mos-sim` with its 16-bit `int`. Details are in `c-patterns.md` and
`llvm-mos.md`.
