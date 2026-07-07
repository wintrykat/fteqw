#!/usr/bin/env bash
# build-engine.sh — build the merged D3D11 + Vulkan + OpenGL FTEQW engine natively
# for Windows-on-ARM (aarch64). Output: engine/release/fteqw64.exe
#
# Renderers (all compiled into ONE binary, runtime-switchable via vid_renderer):
#   * D3D11 — the WoA default (works in the Parallels VM AND on real hardware)
#   * Vulkan — for real Adreno hardware (its ICD ships with the GPU driver; we do
#     NOT bundle a Vulkan runtime, unlike MoltenVK on macOS)
#   * OpenGL + D3D9 — best-effort fallbacks
#
# Why FTE_TARGET=win64 (not a new win_arm64 target): the win64 native block gives
# us exactly the Win32 renderer path (gl_vidnt.o, fs_win32.o, D3D/GL/VK objects)
# with ZERO Makefile edits. clang targets aarch64, so despite the "64"/"win64"
# labels the PE is genuinely ARM64 (0xAA64) — the tests assert this. See
# docs/PORTING-WINDOWS.md for the full rationale and every override.
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

ensure_packages "${1:-}"        # pass --install to auto-install missing packages

ARCH="$(fte_arch)"
[[ -n "$ARCH" ]] || die "could not determine arch triple from clang"
log "target arch: $ARCH  (CLANGARM64 prefix: $CLANGARM64)"

log "building merged D3D11+Vulkan+GL engine (m-rel)…"
fte_make m-rel FTE_TARGET=win64

BIN="$ENGINE/release/fteqw64.exe"
[[ -f "$BIN" ]] || die "build produced no binary at $BIN"

# Must be a genuine ARM64 PE — guards against any accidental x86 regression.
machine="$(llvm-readobj --file-headers "$BIN" 2>/dev/null | grep -o 'IMAGE_FILE_MACHINE_ARM64' | head -1)"
[[ "$machine" == "IMAGE_FILE_MACHINE_ARM64" ]] || die "binary is not ARM64: $(llvm-readobj --file-headers "$BIN" | grep Machine)"

# Both shippable renderers must be genuinely compiled in (not #ifdef'd out).
# grep -c (not -q) so the large nm stream is fully consumed — a -q early-exit
# would SIGPIPE llvm-nm and trip pipefail even when the symbol is present.
(( $(llvm-nm "$BIN" 2>/dev/null | grep -c ' D3D11_Draw_Init$' || true) > 0 )) \
  || die "D3D11 renderer (D3D11_Draw_Init) not present in binary"
(( $(llvm-nm "$BIN" 2>/dev/null | grep -c ' VK_Init$' || true) > 0 )) \
  || die "Vulkan renderer (VK_Init) not present in binary"

ok "engine built: $BIN (ARM64, D3D11 + Vulkan + GL)"
