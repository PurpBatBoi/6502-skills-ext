# Raising IL to Portable C99

This file covers the C-specific traps, the flag helpers, the faithful
interpreter used as a test oracle, the idiom catalog, the platform layer, and
verification. Everything here is **portable C99**: it builds with a host
compiler (gcc/clang) *and* with llvm-mos for the 6502. The helper and idiom
snippets were compiled and run both ways: on host gcc (32-bit `int`, clean
under `-Wconversion -Wpedantic`) and in the llvm-mos 6502 simulator (16-bit
`int`). The oracle needs a 64 KiB array, so it was tested on the host only. The
6502-specific backend details are in `llvm-mos.md`.

Contents: [C traps](#the-c-traps-read-first) · [Flag helpers](#flag-helpers) ·
[Faithful oracle](#faithful-cpu-oracle-host-only) · [Idioms](#idiom-catalog) ·
[Platform layer](#platform-layer-the-only-part-that-differs) ·
[Self-modifying code](#self-modifying-code) · [Verification](#verification) ·
[Checklist](#emit-checklist)

## The C traps (read first)

C's integer rules cause more bad 6502 ports than anything else. Rust panics
or refuses to compile in these cases; **C compiles them silently and gets the
wrong answer**. Every rule below follows from one fact: arithmetic on `uint8_t`
and `uint16_t` happens in `int`.

| Trap | Wrong | Right | Why |
|------|-------|-------|-----|
| 8-bit results don't wrap | `a = a + 1;` then testing `a + 1 == 0` | `a = (uint8_t)(a + 1u);` | `uint8_t` operands become `int`; `0xFF + 1` is `256` until you cast back |
| `~` on a byte | `adc8(a, ~m, c)` | `adc8(a, (uint8_t)~m, c)` | `~m` is an `int` (`0xFF…FC` for m=3), so carry comes out wrong; verified |
| Address arithmetic | `mem[addr + 1]` | `mem[(uint16_t)(addr + 1u)]` | `0xFFFF + 1` is `0x10000` in `int`, indexing past a 64 KiB array; the 6502 wraps to `$0000` |
| Zero-page index | `mem[zp + x]` | `mem[(uint8_t)(zp + x)]` | `LDA $FF,X` with X=1 reads `$0000` on the 6502 |
| Word from bytes | `lo \| (hi << 8)` | `(uint16_t)(lo \| ((uint16_t)hi << 8))` | With 16-bit `int` (llvm-mos), `0xFF << 8` overflows `int`, which is **undefined behavior** |
| 16×16 multiply | `uint16_t p = a * b;` (wanting 32 bits) | `(uint32_t)a * b` | On a 32-bit-`int` host, `uint16_t` promotes to *signed* `int`; `0xFFFF * 0xFFFF` overflows, undefined behavior |
| Signed types | `char`, `int` for register values | `uint8_t`, `uint16_t` only | `char` signedness varies by compiler; signed overflow is undefined behavior |
| Type punning | `*(uint16_t *)&mem[p]` | the word helpers below | Breaks on big-endian hosts and on strict-aliasing rules |
| Overlapping copy | `memcpy(dst, src, n)` | keep the loop, or `memmove` only if no overlap was intended | See [memcpy / memset](#memcpy--memset); a forward loop with `dst = src + 1` is a **fill** |
| Loop counter type | `int i` compared against a byte | `uint8_t`/`unsigned`, with explicit 0→256 handling | See the loop trip-count rules in `il-spec.md` |

Rule of thumb: **every assignment of an arithmetic result to `uint8_t` or
`uint16_t` gets an explicit cast.** It documents the wrap, and `-Wconversion`
then reports every place you missed.

## Flag helpers

Use these only where a flag is live (see "flag liveness" in `il-spec.md`).

```c
#include <stdint.h>
#include <stdbool.h>

typedef struct { uint8_t r; bool c, v; } alu8;   /* result, carry out, overflow */

/* ADC, binary mode */
static alu8 adc8(uint8_t a, uint8_t m, bool c)
{
    unsigned s = (unsigned)a + m + (c ? 1u : 0u);   /* 0..511 fits a 16-bit unsigned */
    alu8 o;
    o.r = (uint8_t)s;
    o.c = s > 0xFFu;
    o.v = ((a ^ o.r) & (m ^ o.r) & 0x80u) != 0;     /* signed overflow */
    return o;
}

/* SBC, binary mode: ADC of the complement. The cast is mandatory. */
static alu8 sbc8(uint8_t a, uint8_t m, bool c) { return adc8(a, (uint8_t)~m, c); }

/* CMP/CPX/CPY: C = reg >= m (unsigned); N/Z from reg - m */
static bool cmp_c(uint8_t reg, uint8_t m) { return reg >= m; }

/* Packed BCD, valid BCD inputs only (decimal mode; never on the NES 2A03) */
static uint8_t bcd_add(uint8_t a, uint8_t b, bool *carry)
{
    unsigned lo = (a & 0x0Fu) + (b & 0x0Fu) + (*carry ? 1u : 0u);
    unsigned hi = (unsigned)(a >> 4) + (unsigned)(b >> 4);
    if (lo > 9u) { lo -= 10u; hi++; }
    *carry = hi > 9u;
    if (*carry) hi -= 10u;
    return (uint8_t)((hi << 4) | lo);
}

static uint8_t bcd_sub(uint8_t a, uint8_t b, bool *carry)   /* carry = no borrow, as SBC */
{
    int lo = (a & 0x0F) - (b & 0x0F) - (*carry ? 0 : 1);
    int hi = (a >> 4) - (b >> 4);
    if (lo < 0) { lo += 10; hi--; }
    *carry = hi >= 0;
    if (hi < 0) hi += 10;
    return (uint8_t)((hi << 4) | lo);
}
```

These were checked exhaustively: `sbc8`'s carry matches `a - m - !c >= 0` for
all 131,072 inputs, and `bcd_add(0x99, 0x01)` = `0x00` with carry set.

## Faithful CPU oracle (host only)

When the intent is unclear, when code modifies itself, or when you need
something to test against, port the routine literally onto an explicit CPU
state. It's ugly on purpose: it is provably equal to the original, and the
idiomatic version is tested against it. A 64 KiB array doesn't fit on the
6502, so the oracle only runs on the host.

```c
struct cpu {
    uint8_t a, x, y, sp;
    uint16_t pc;
    bool n, v, d, i, z, c;
    uint8_t mem[0x10000];
};

static void set_nz(struct cpu *s, uint8_t v) { s->z = (v == 0); s->n = (v & 0x80u) != 0; }
static void op_lda(struct cpu *s, uint8_t m) { s->a = m; set_nz(s, m); }
static void op_adc(struct cpu *s, uint8_t m)
{
    if (s->d) { s->a = bcd_add(s->a, m, &s->c); set_nz(s, s->a); return; } /* NMOS N/V/Z: see il-spec.md */
    alu8 o = adc8(s->a, m, s->c);
    s->a = o.r; s->c = o.c; s->v = o.v; set_nz(s, o.r);
}
/* … one function per instruction, mirroring il-spec.md; on a 2A03 ignore d */

static uint8_t rd_zp_ind_y(const struct cpu *s, uint8_t zp)     /* LDA (zp),Y */
{
    uint16_t ptr = (uint16_t)(s->mem[zp] | ((uint16_t)s->mem[(uint8_t)(zp + 1u)] << 8));
    return s->mem[(uint16_t)(ptr + s->y)];   /* pointer high byte wraps in page 0 */
}
```

## Idiom catalog

### Words, 16-bit add / subtract / compare

```c
static uint16_t rd16(const uint8_t *p)        { return (uint16_t)(p[0] | ((uint16_t)p[1] << 8)); }
static void     wr16(uint8_t *p, uint16_t v)  { p[0] = (uint8_t)v; p[1] = (uint8_t)(v >> 8); }

/* CLC / LDA $06 / ADC $08 / STA $0A / LDA $07 / ADC $09 / STA $0B */
wr16(&zp[0x0A], (uint16_t)(rd16(&zp[0x06]) + rd16(&zp[0x08])));
```

`SEC / SBC lo / SBC hi`, followed by a test of C or Z, is a 16-bit compare:
write it as `<`, `>=` or `==` on the rebuilt `uint16_t` values. If the
carry out of the high byte is live, return it as well, e.g.
`bool carry = (sum32 > 0xFFFFu)` from a `uint32_t` sum.

### Shift-add multiply, subtract-shift divide

An 8-round loop that shifts and conditionally adds is a multiply. A loop that
trial-subtracts and shifts is a divide:

```c
uint16_t p8  = (uint16_t)((uint16_t)a * b);   /* 8x8 -> 16: fine on both int widths */
uint32_t p16 = (uint32_t)a16 * b16;           /* 16x16 -> 32: the cast is required */
uint8_t  q = (uint8_t)(n / d), r = (uint8_t)(n % d);
```

Before collapsing a loop, check its rounding and range against the original.
If the original guards against division by zero, keep the guard. On llvm-mos,
`*`, `/` and 32-bit math compile to library calls; for hot paths, see
`llvm-mos.md`.

### `(zp),Y` walks → pointer or index loops

```c
for (i = 0; i < len; i++) process(buf[i]);              /* length-bounded */
for (i = 0; s[i] != 0; i++) emit(s[i]);                 /* zero-terminated */
do { ch = s[i++]; emit((uint8_t)(ch & 0x7Fu)); } while (!(ch & 0x80u));
                                                        /* last char has bit 7 set (DCI) */
```

The original's `Y` is a `uint8_t`, so a 6502 walk never covers more than 256
bytes per pointer. If the source advances the pointer's high byte (`INC ptr+1`),
it walks a longer buffer; make the C index a `uint16_t`.

### memcpy / memset

`LDA (src),Y / STA (dst),Y / INY / BNE` is a copy, and a constant store loop is
a fill:

```c
memcpy(dst, src, n);   /* only if the regions cannot overlap */
memset(buf, v, n);
```

**Watch for overlap.** A 6502 *forward* copy with `dst = src + 1` spreads
`src[0]` across the whole range. On the original hardware that's a fill.
Verified: `{AA,01,02,03}` becomes `{AA,AA,AA,AA}`. In C, `memcpy` on
overlapping memory is undefined behavior, and `memmove` does a true copy, so
it gives a *different* result. When the regions can overlap, keep the explicit
loop, or use `memset` if a fill is the intent.

### Jump tables and RTS trampolines

A `JMP (table)` pointer, or a "push target-1 then RTS" table, becomes a
`switch` or a function-pointer table:

```c
switch (cmd) { case 0: do_move(); break; case 1: do_jump(); break; default: idle(); }

typedef void (*handler)(void);
static const handler table[] = { do_move, do_jump, idle };
table[cmd]();     /* bounds-check cmd if the original didn't guarantee it */
```

Recover one case per entry in the address table. Both forms work on llvm-mos.
A function called through a pointer still gets a static frame (verified);
recursion is what forces the slower software stack (see `llvm-mos.md`).

### BCD arithmetic

Port decimal-mode regions with `bcd_add`/`bcd_sub`. Keep the values as
packed BCD if the display code reads nibbles directly; otherwise convert to
binary at the edges. Don't silently treat BCD as binary. NES code never uses
BCD, because the 2A03 ignores the D flag.

### Bit masks

`LDA flags / AND #mask / BNE` tests a bit. `ORA #mask` and `AND #~mask` set and
clear bits. When the bits have known meanings, give them names:

```c
enum { F_ALIVE = 0x01u, F_FACING_LEFT = 0x02u };
if (obj->flags & F_ALIVE) …;
obj->flags = (uint8_t)(obj->flags & (uint8_t)~F_FACING_LEFT);   /* cast both: ~ again */
```

## Platform layer (the only part that differs)

Every classified hardware or ROM access (see the 6502-memory-map skill)
becomes a call into one header. The **core C never touches an address
directly.** That one rule is what lets the same core build for the host and
for the 6502.

```c
/* platform.h — host and llvm-mos backends behind one interface */
#ifndef PLATFORM_H
#define PLATFORM_H
#include <stdint.h>

#if defined(__mos__) && defined(__C64__)
#include <c64.h>
#include <cbm.h>
static inline void plat_chrout(uint8_t ch)     { cbm_k_chrout(ch); }      /* JSR $FFD2 */
static inline void plat_set_border(uint8_t c)  { VIC.bordercolor = c; }   /* STA $D020 */
#else
/* host: implemented in host_platform.c — log to a trace, draw with SDL, or mock in tests */
void plat_chrout(uint8_t ch);
void plat_set_border(uint8_t c);
#endif

#endif
```

`JSR $FFD2` becomes `plat_chrout(a)`; `STA $D020` becomes `plat_set_border(a)`.
Add one function per service the code actually uses. On the host, a mock
that records calls turns hardware behavior into something a test can assert
on. The 6502-side backends for each platform (C64, Atari, Apple II, NES) are in
`llvm-mos.md`.

A `JSR` into a known floating-point ROM routine (Applesoft FADD/FMULT, Atari's
BCD floating-point package) becomes host `double` math. If the result must
match the original bit for bit, reimplement the 5- or 6-byte float format
instead. On the 6502 build, keep calling the ROM.

## Self-modifying code

A store into the instruction stream can't be expressed as static C control
flow. In order of preference:

1. **Recover the intent.** A patched operand is usually an array index
   (`table[i]`) or a function pointer (a `switch`).
2. **Host:** run that region on the faithful `struct cpu` oracle and call
   into it.
3. **6502 build:** leave the region as assembly in a `.s` file linked into
   the llvm-mos program. Code that modifies itself must run from RAM. See
   `llvm-mos.md` for the calling convention.

Mark every self-modifying site explicitly in the port; never let one pass
silently.

## Verification

1. **Differential test on the host.** Run the oracle and the idiomatic port on
   the same inputs and compare what's observable: memory, the platform-call
   trace, return values. Sweep exhaustively where you can (all 65,536 byte
   pairs take milliseconds) and add boundary cases: `0x00`, `0xFF`, carry
   in/out, `$xxFF` page crossings, and BCD values `0x09+0x01` and `0x99+0x01`.
2. **Warnings as the first test:**
   `gcc -std=c99 -Wall -Wextra -Wpedantic -Wconversion` (or clang). Every
   `-Wconversion` warning is a missing wrap cast.
3. **Undefined-behavior checks.**
   - Linux/macOS: `-fsanitize=undefined,address`.
   - MinGW has no UBSan runtime (`cannot find -lubsan`). Use
     `-fsanitize=undefined -fsanitize-undefined-trap-on-error`, which needs no
     runtime and traps (exit code 132) on, for example, signed overflow.
     Verified on gcc 16 / MinGW.
4. **Run the same tests on a 6502.** Build the test harness with
   `mos-sim-clang` and run it under `mos-sim`. `int` is 16-bit there, so
   promotion bugs that a 32-bit host hides show up. `printf` output and the
   exit code both come back to the shell (see `llvm-mos.md`).
5. If you reimplemented a ROM routine, test it against its documented
   behavior (for example, CHROUT control codes), not against the ROM bytes.

## Emit checklist

- [ ] CPU (6502/6510/2A03), platform, and decimal-mode regions identified.
- [ ] Lifted to faithful IL; flags explicit.
- [ ] Dead flags removed (proven, not assumed).
- [ ] Idioms collapsed; byte pairs → `uint16_t`; buffers → arrays/pointers.
- [ ] Only `uint8_t`/`uint16_t`/`unsigned` for machine values; every narrowing
      assignment cast; clean under `-Wconversion`.
- [ ] `~` operands cast back to `uint8_t`; address math cast to `uint16_t`.
- [ ] Overlapping copies kept as loops, not `memcpy`.
- [ ] Every hardware/ROM access goes through `platform.h`.
- [ ] Self-modifying sites handled explicitly.
- [ ] Differential test passes on the host, under the UB checks, and on
      `mos-sim`.
