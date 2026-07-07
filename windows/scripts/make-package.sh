#!/usr/bin/env bash
# make-package.sh — assemble engine/release output into a self-contained package
# folder that runs on any Windows-on-ARM device with NO dependency on MSYS2.
# Requires build-engine.sh (and optionally build-plugins.sh) to have run first.
#
# Windows makes this far simpler than macOS: the loader resolves DLLs next to the
# .exe first, so we just copy the non-system DLL closure beside fteqw.exe — no
# install_name_tool / rpath surgery, no signing dance.
#
# Cosmetic renames: the win64 build labels artifacts "64"/"_x64" (a misnomer on
# arm64); we drop that here → fteqw.exe, fteplug_<name>.dll.
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

PKG="$FTEQW_PKG"
BIN="$ENGINE/release/fteqw64.exe"
[[ -f "$BIN" ]] || die "engine not built — run build-engine.sh first"

# Plugins are optional; package whichever were built (default names).
plugins=(); for p in ffmpeg qi; do [[ -f "$ENGINE/release/fteplug_${p}_x64.dll" ]] && plugins+=("$p"); done

log "assembling self-contained package: $PKG"
rm -rf "$PKG"; mkdir -p "$PKG"

cp "$BIN" "$PKG/fteqw.exe"
for p in "${plugins[@]}"; do cp "$ENGINE/release/fteplug_${p}_x64.dll" "$PKG/fteplug_$p.dll"; done
ok "engine + ${#plugins[@]} plugin(s) copied (renamed to arm64-neutral names)"

# --- default renderer: D3D11 -------------------------------------------------
# The merged binary otherwise auto-selects OpenGL, which is the weak/fallback path
# on Windows-on-ARM and misrenders on the Parallels virtual GPU (red/green font
# fringing). D3D11 is the universal, reliable default (brief §1). We ship it as an
# autoexec.cfg in FTE's base "fte" gamedir — it runs last in the config order
# (default.cfg → config.cfg → autoexec.cfg), so it reliably wins. A real-device
# owner can switch to Vulkan by editing this one line.
mkdir -p "$PKG/fte"
cat > "$PKG/fte/autoexec.cfg" <<'CFG'
// FTEQW Windows-on-ARM default: prefer the D3D11 renderer.
// D3D11 is the universal, reliable path on Windows-on-ARM (and the only one
// validated on the Parallels virtual GPU — OpenGL misrenders there). On a real
// Adreno device you may switch to Vulkan for best results: change the line below
// to `vid_renderer vk`, or delete it to use the engine's own default.
vid_renderer d3d11
CFG
ok "default renderer set to D3D11 (fte/autoexec.cfg)"

# --- DLL closure -------------------------------------------------------------
# Union the recursive dependency closure of the exe AND every plugin (plugins are
# dlopen'd at runtime, so their deps — notably ffmpeg's avcodec/avformat/avutil/
# swscale and their codec sub-deps — aren't reachable from the exe alone).
# Copy every dependency that resolves under the MSYS2 tree; leave OS DLLs
# (kernel32, d3d11, dxgi, vulkan-1 …) unbundled — they belong to Windows.
log "resolving DLL closure (ntldd -R)…"
tmplist="$(mktemp)"
for pe in "$PKG/fteqw.exe" "$PKG"/fteplug_*.dll; do
  [[ -e "$pe" ]] || continue
  ntldd -R "$pe" 2>/dev/null
done | grep -iE '=>[^=]*msys64' | sed -E 's/.*=> *//; s/ \(0x[0-9a-fA-F]*\)//' | sort -u > "$tmplist"

count=0
while IFS= read -r dllpath; do
  [[ -n "$dllpath" ]] || continue
  src="$(cygpath -u "$dllpath" 2>/dev/null || echo "$dllpath")"
  [[ -f "$src" ]] || { warn "closure entry not found on disk: $dllpath"; continue; }
  cp -n "$src" "$PKG/" && count=$((count+1))
done < "$tmplist"
rm -f "$tmplist"
ok "bundled $count non-system DLL(s)"

mkdir -p "$FTEQW_DATA"

# --- self-containment audit --------------------------------------------------
# Re-resolve the closure with the MSYS2 bin dirs REMOVED from PATH and cwd=$PKG,
# so the only place a non-system DLL can come from is the package itself. Any
# dependency still resolving under msys64 (or reported "not found" for a
# non-system name) means the closure is incomplete.
log "auditing self-containment…"
audit_path="$(echo "$PATH" | tr ':' '\n' | grep -ivE 'msys64|clangarm64' | paste -sd: -)"
leaks=0
for pe in fteqw.exe fteplug_*.dll; do
  [[ -e "$PKG/$pe" ]] || continue
  n="$(cd "$PKG" && PATH="$audit_path" ntldd -R "$pe" 2>/dev/null | grep -ciE 'msys64|clangarm64' || true)"
  (( n == 0 )) || { warn "$pe still references MSYS2 in $n dependency(ies)"; leaks=$((leaks+n)); }
done
(( leaks == 0 )) || die "self-containment audit failed: $leaks external reference(s) remain"
ok "self-contained: 0 MSYS2 references across the package ($(ls "$PKG"/*.dll 2>/dev/null | wc -l | tr -d ' ') bundled DLLs)"

log "package ready: $PKG"
printf '%sPut Quake data (id1/, qw/, mods) in:%s %s\n' "$C_CYAN" "$C_0" "$FTEQW_DATA"
