#!/usr/bin/env bash
#
# run-tests.sh — build and run a 6502-to-C test harness twice:
#   1. host:  C99, -Wall -Wextra -Wpedantic -Wconversion -Werror, plus
#             undefined-behavior checks in trap mode (no sanitizer runtime
#             needed, so it also works on MinGW)
#   2. 6502:  llvm-mos mos-sim (16-bit int), if llvm-mos is installed
#
# Usage:
#   run-tests.sh tests.c [port.c host_platform.c ...]
#
# The harness's main() returns 0 on success, non-zero on failure.
# Env overrides: CC (host compiler; clang gives better -Wconversion warnings),
# CFLAGS_EXTRA (appended to host flags), LLVM_MOS (llvm-mos install dir,
# default C:/llvm-mos or /opt/llvm-mos), SKIP_SIM=1 (host-only tests, e.g.
# the faithful oracle, whose 64 KiB array does not fit on the 6502).
#
set -uo pipefail

[ $# -ge 1 ] || { sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }

out="$(mktemp -d)"
trap 'rm -rf "$out"' EXIT
status=0

# --- host ---------------------------------------------------------------
cc="${CC:-$(command -v gcc || command -v clang || command -v cc)}"
if [ -z "$cc" ]; then echo "host: no C compiler found (set CC)" >&2; exit 2; fi
# shellcheck disable=SC2086
if "$cc" -std=c99 -Wall -Wextra -Wpedantic -Wconversion -Werror -O1 \
      -fsanitize=undefined -fsanitize-undefined-trap-on-error \
      ${CFLAGS_EXTRA:-} "$@" -o "$out/host.exe"; then
  "$out/host.exe"; rc=$?
  if [ $rc -eq 0 ]; then echo "host: PASS"
  elif [ $rc -eq 132 ] || [ $rc -eq 133 ] || [ $rc -eq 134 ]; then
    echo "host: UNDEFINED BEHAVIOR trapped (exit $rc) — rerun under a debugger to find it"; status=1
  else echo "host: FAIL (exit $rc)"; status=1; fi
else
  echo "host: BUILD FAILED (fix warnings first: -Wconversion = missing wrap casts)"; status=1
fi

# --- 6502 (llvm-mos simulator) -----------------------------------------
find_tool() {  # name -> path; checks PATH (plain or .bat) then $LLVM_MOS/bin
  local n="$1" d
  command -v "$n" 2>/dev/null && return
  command -v "$n.bat" 2>/dev/null && return
  for d in "${LLVM_MOS:-}" "C:/llvm-mos" "/c/llvm-mos" "/opt/llvm-mos"; do
    [ -n "$d" ] || continue
    for f in "$d/bin/$n" "$d/bin/$n.bat" "$d/bin/$n.exe"; do [ -f "$f" ] && { echo "$f"; return; }; done
  done
  return 1
}
mcc="$(find_tool mos-sim-clang)"; sim="$(find_tool mos-sim)"
if [ "${SKIP_SIM:-0}" = 1 ]; then
  echo "6502: SKIPPED (SKIP_SIM=1)"
elif [ -z "$mcc" ] || [ -z "$sim" ]; then
  echo "6502: SKIPPED (llvm-mos not found; set LLVM_MOS)"
elif "$mcc" -Os -std=c99 -Wall "$@" -o "$out/sim.bin"; then
  "$sim" "$out/sim.bin"; rc=$?
  if [ $rc -eq 0 ]; then echo "6502: PASS (mos-sim, 16-bit int)"
  else echo "6502: FAIL (exit $rc) — passes on host? suspect 16-bit int promotion"; status=1; fi
else
  echo "6502: BUILD FAILED"; status=1
fi

exit $status
