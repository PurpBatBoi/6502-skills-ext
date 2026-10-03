# The llvm-mos Backend: C That Compiles Back to the 6502

This is the 6502 side of the platform layer in `c-patterns.md`. The core C
stays identical; this file covers what changes when that core targets a real
6502 machine through llvm-mos. Every claim here was checked by compiling or
running against **llvm-mos clang 24.0.0git (SDK at `C:\llvm-mos`)**. If your
SDK version differs, re-check with `-fno-lto -S` (see
[Inspecting output](#inspecting-output)).

Contents: [Drivers](#drivers-and-predefined-macros) ·
[Data model](#data-model-and-costs) · [Zero page](#zero-page) ·
[Hardware](#hardware-access-per-platform) · [Inline asm](#inline-assembly-for-rom-calls) ·
[Calling convention](#calling-convention-for-s-files) ·
[`.s` syntax](#writing-s-files-gnu-as-syntax) · [Inspecting output](#inspecting-output) · [Testing on a 6502](#testing-on-a-6502-mos-sim)

## Drivers and predefined macros

Each platform has its own compiler driver, and each driver predefines macros
that `platform.h` can switch on:

| Platform | Driver | Predefined |
|----------|--------|------------|
| Commodore 64 | `mos-c64-clang` | `__mos__`, `__C64__`, `__CBM__` |
| Atari 8-bit | `mos-atari8-dos-clang` (DOS executable), `mos-atari8-cart-std-clang` (cartridge) | `__mos__`, `__ATARI__` |
| Apple II | `mos-apple2-clang` | `__mos__`, `__APPLE2__` |
| NES | `mos-nes-<mapper>-clang`: `nrom`, `cnrom`, `unrom`, `unrom-512`, `mmc1`, `mmc3`, `action53`, `gtrom`; link with `-lneslib` | `__mos__`, `__NES__`, `__NES_NROM__` (per mapper) |
| 6502 simulator | `mos-sim-clang`, run with `mos-sim` | `__mos__` |

- Pass **`-std=c99`**; the drivers default to C17.
- On Windows the drivers are `.bat` wrappers in `C:\llvm-mos\bin`.
- To scaffold a whole NES project (CMake, iNES header, mapper choice), use
  the nes-llvm-mos-init skill.

Typical build: `mos-c64-clang -Os -std=c99 -Wall core.c platform_c64.c -o game.prg`.

## Data model and costs

- **`int` is 16-bit, `long` is 32-bit, and pointers are 16-bit.**
  - `unsigned` holds only 0-65535.
  - `uint16_t` promotes to `unsigned` here but to `int` on the host. The
    casts in `c-patterns.md` are written to be correct under both rules.
- **`*`, `/`, `%` are library calls.** `uint8_t × uint8_t` compiles to
  `jmp __mulhi3`, and `uint8_t / uint8_t` to `jmp __udivqi3`. On hot paths:
  - keep the original's shift-add loop or lookup table;
  - shifts and masks by constants are cheap.
- 32-bit and floating-point math run in software. Use them only where the
  original did multi-byte or floating-point math, or route them to the ROM's
  floating-point package instead.
- **Locals:** a non-recursive function gets a static frame (`.L<fn>_sstk`),
  even when it's called through a function pointer (verified). **Recursion**
  moves the function onto the software stack (`__rc0`/`__rc1`), which is
  slower and bigger. 6502 code is almost never recursive, so keep the port
  that way.
- Use `uint8_t` for loop counters and indexes wherever the original used `X`
  or `Y`. They compile to real `X`/`Y` register loops.

## Zero page

Mark variables the original kept in zero page with the `__zp` qualifier:

```c
static uint8_t __zp counter;    /* accessed as mos8(counter): zero-page addressing (verified) */
```

Zero page is scarce. The compiler's imaginary registers (`__rc0…`) live there,
and so do the OS's variables: on the C64 target, the map file shows the usable
range as `__basic_zp_start = $02` to `__basic_zp_end = $90`. Spend `__zp` on
pointers and hot counters, not on bulk data.

## Hardware access per platform

The core never touches hardware directly; `platform.h` does. On the 6502 side
that is a `volatile` access. Reads count too: a soft-switch *read* must stay a
read. Verified: `(void)*(volatile uint8_t *)0xC050;` compiles to
`ldx 49232`, which is `LDX $C050`.

| Platform | SDK header | What it gives you |
|----------|------------|-------------------|
| C64 | `<c64.h>`, `<cbm.h>` | `VIC`, `SID`, `CIA1`, `CIA2` register structs (`VIC.bordercolor = c` → `stx $D020`, verified); KERNAL wrappers `cbm_k_chrout`, `cbm_k_chrin`, `cbm_k_getin`, `cbm_k_setnam`, `cbm_k_open`, … |
| Atari 8-bit | `<atari.h>` | `ANTIC`, `GTIA_READ`/`GTIA_WRITE`, `POKEY_READ`/`POKEY_WRITE`, `PIA`, and the `OS` shadow-register struct (`OS.color4` = `$02C8`) |
| Apple II | `<apple2.h>` | only ProDOS constants. Use raw `volatile` for soft switches and inline asm for Monitor ROM calls (below). |
| NES | `<neslib.h>`, `<nesdoug.h>` (+ `-lneslib`) | `pal_col`, `ppu_on_all`, `ppu_wait_nmi`, `oam_*`, … (a frame-based API, not raw registers). For raw PPU access use `volatile` on `$2000-$2007`. |

Write shadow registers when the original did: on the Atari, `STA $02C8` and
`STA $D01A` are different effects, and the OS copies the shadow to hardware
every frame.

```c
/* platform.h, Apple II branch */
#elif defined(__mos__) && defined(__APPLE2__)
static inline void plat_chrout(uint8_t ch)
{   __asm__ volatile ("jsr $fded" : "+a"(ch) : : "x", "y", "p", "memory"); }   /* COUT */
static inline void plat_text_mode(void) { (void)*(volatile uint8_t *)0xC051; } /* TXTSET */
```

## Inline assembly for ROM calls

```c
__asm__ volatile ("jsr $fd0c" : "+a"(a), "+x"(x), "+y"(y) : : "p", "memory");
```

- The constraints `"a"`, `"x"` and `"y"` bind a C value to that register; all
  three are verified to load the register before the `jsr`.
- Use **`"+a"`** (read and clobbered) for a register that is both an input and
  trashed by the routine. A register that is already an operand **must not**
  appear in the clobber list. llvm-mos rejects that with "asm-specifier for
  input or output variable conflicts with asm clobber list".
- Clobber `"p"` (flags) and whichever of `"x"`/`"y"` the ROM routine trashes.
  Add `"memory"` whenever the routine reads or writes RAM the compiler can
  see.

## Calling convention (for `.s` files)

A region you can't port (self-modifying code, cycle-exact timing, raster
tricks) can stay as assembly in a `.s` file linked into the program. This is
what the compiler does with this SDK, read from its own output:

| What | Where |
|------|-------|
| 1st / 2nd 8-bit argument | `A` / `X` |
| further 8-bit arguments | `__rc2`, `__rc3`, … |
| 16-bit argument | `A` (low), `X` (high) |
| pointer argument | `__rc2`/`__rc3` |
| 8-bit return | `A` |
| 16-bit return | `A` (low), `X` (high) |

For anything more complex, write the C prototype, compile a tiny caller with
`-fno-lto -S`, and copy what the compiler emits. Don't guess. Code that
modifies itself must also run from RAM. On cartridge targets (NES, Atari
cart), copy it into RAM at startup before calling it.

## Writing `.s` files (GNU-as syntax)

The llvm-mos assembler is GNU-assembler compatible. That means `.macro`,
`.if`, `.section` and `.global` work, but ca65 and Merlin directives don't. It
assembles the NMOS opcode set and computes 6502 relative branch offsets
itself. Hand the `.s` file to the same driver as the C files. This example
was built with the C caller below and run on `mos-sim` (it returned 33):

```asm
; uint8_t add3(uint8_t a, uint8_t b) — a in A, b in X, result in A
.macro addk k
    clc
    adc #\k
.endm
.section .text.add3,"ax",@progbits
.global add3
add3:
    stx mos8(__rc2)    ; mos8() forces zero-page addressing (2-byte STX)
    clc
    adc mos8(__rc2)
    addk $03           ; $ hex prefix works, as does 0x
    rts
```

```sh
mos-c64-clang -Os -std=c99 main.c add3.s -o game.prg
```

Zero page versus absolute addressing, checked with `llvm-objdump`:

| Operand | Encoded as |
|---------|------------|
| literal `$10` | zero page (2 bytes) |
| literal `$1234` | absolute (3 bytes) |
| symbol defined in a `.zp*` section of the same file | zero page |
| **external symbol** (e.g. `__rc2`, or a `__zp` C variable) | **absolute** — wrap it in `mos8(sym)` to get zero page |

That last row is the trap: without `mos8()` the code still works but is a
byte longer and a cycle slower per access, which matters in hot loops ported
from zero-page code.

Target-specific directive: `.mos_addr_asciz <expr>, <digits>` emits a
fixed-length decimal ASCII string plus a NUL (verified: `1234, 4` →
`"1234\0"`). Its main use is the C64 BASIC `SYS` header. When running the
standalone assembler (`llvm-mc`), select the target with `-triple mos`.

## Inspecting output

- `mos-c64-clang -Os -std=c99 -fno-lto -S file.c -o -` prints 6502 assembly.
  Without `-fno-lto`, `-S` emits LLVM IR, because link-time optimization is
  on by default.
- `-Wl,--Map=out.map` writes the linker map: section sizes, zero-page range,
  and `__stack`.
- Compare the port's hot loops against the original's cycle counts. `-Os`
  is usually the right default on the 6502.

## Testing on a 6502 (`mos-sim`)

The same test harness that runs on the host also runs on a simulated 6502:

```sh
mos-sim-clang -Os -std=c99 tests.c core.c -o tests.bin
mos-sim tests.bin          # printf goes to stdout; main's return value is the exit code
```

Verified: the `c-patterns.md` snippets pass here (`sizeof(int) == 2`), and
`return 7;` from `main` comes back as exit code 7. This is where integer
promotion bugs that a 32-bit host hides get caught. The simulator has no
C64/Atari/Apple/NES hardware, so test the platform layer on an emulator.
