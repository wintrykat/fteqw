# 50-package.sh — the package is well-formed and fully self-contained.
# Tier 1 (always runs). This is the Windows analog of the macOS bundle test:
# the definitive proof that nothing loads from MSYS2 (C:\msys64).
section "Package & self-containment"

# Structure — arm64-neutral names, no leftover "64"/"_x64" build labels.
check    "fteqw.exe in package"          test -f "$PKG/fteqw.exe"
check    "plugins renamed (fteplug_ffmpeg.dll)" test -f "$PKG/fteplug_ffmpeg.dll"
check    "no leftover fteqw64.exe"       bash -c "! test -e '$PKG/fteqw64.exe'"
check    "no leftover _x64 plugin names" bash -c "! ls '$PKG'/*_x64.dll >/dev/null 2>&1"

# Default renderer must be D3D11 — the merged binary otherwise auto-selects the
# weak OpenGL path, which misrenders on the virtual GPU (red/green font fringing).
check    "ships D3D11 default (fte/autoexec.cfg)" test -f "$PKG/fte/autoexec.cfg"
contains "default renderer is d3d11"     "vid_renderer d3d11" \
         "$(cat "$PKG/fte/autoexec.cfg" 2>/dev/null)"

# Some non-system DLLs were bundled (closure is non-empty).
nbundled="$(ls "$PKG"/*.dll 2>/dev/null | wc -l | tr -d ' ')"
check    "non-system DLLs bundled"       test "$nbundled" -gt 0
# Representative deps that MUST be local (clang runtime + an ffmpeg lib).
check    "libc++ runtime bundled"        bash -c "ls '$PKG'/libc++*.dll >/dev/null 2>&1"
check    "ffmpeg avcodec bundled"        bash -c "ls '$PKG'/avcodec-*.dll >/dev/null 2>&1"

# Definitive self-containment: resolve every PE's closure with the MSYS2 bin dirs
# removed from PATH and cwd=$PKG. Any dependency still resolving under msys64 means
# the package would break on a machine without MSYS2.
audit_path="$(echo "$PATH" | tr ':' '\n' | grep -ivE 'msys64|clangarm64' | paste -sd: -)"
leaks=0
for pe in "$PKG"/fteqw.exe "$PKG"/fteplug_*.dll; do
  [[ -e "$pe" ]] || continue
  n="$(cd "$PKG" && PATH="$audit_path" ntldd -R "$(basename "$pe")" 2>/dev/null | grep -ciE 'msys64|clangarm64' || true)"
  leaks=$((leaks+n))
done
check    "no dependency resolves to MSYS2 (self-contained)" test "$leaks" -eq 0

# Portable ZIP was produced.
check    "portable ZIP exists" bash -c "ls '$REPO'/windows/dist/FTEQW-*-win-arm64.zip >/dev/null 2>&1"
