#!/usr/bin/env bash
# make-installer.sh — build the Inno Setup installer from the self-contained
# package. Requires the package (run build-all.sh first) and Inno Setup's ISCC
# compiler on the machine. The portable ZIP from build-all.sh is the always-ship
# artifact; this installer is the recommended installable form.
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

[[ -f "$FTEQW_PKG/fteqw.exe" ]] || die "no package at $FTEQW_PKG — run build-all.sh first"

# Locate ISCC (PATH, or the standard install locations).
ISCC=""
if have ISCC; then ISCC="ISCC"; else
  for c in "/c/Program Files (x86)/Inno Setup 6/ISCC.exe" "/c/Program Files/Inno Setup 6/ISCC.exe"; do
    [[ -x "$c" ]] && { ISCC="$c"; break; }
  done
fi
if [[ -z "$ISCC" ]]; then
  warn "Inno Setup (ISCC) not found. Install it (winget install JRSoftware.InnoSetup)"
  warn "or ship the portable ZIP from build-all.sh. Skipping installer."
  exit 0
fi

VER="$(cd "$REPO" && git describe --always --long --dirty 2>/dev/null || echo dev)"
ISS="$REPO/windows/installer/fteqw.iss"
log "building installer with ISCC (v$VER)…"
"$ISCC" "//DSrcDir=$(cygpath -w "$FTEQW_PKG")" "//DAppVersion=$VER" "$(cygpath -w "$ISS")"

OUT="$REPO/windows/dist/FTEQW-$VER-win-arm64-setup.exe"
[[ -f "$OUT" ]] || die "installer not produced at $OUT"
ok "installer: $OUT ($(du -h "$OUT" | cut -f1))"
warn "unsigned — sign with an EV/OV Authenticode cert for distribution (avoids SmartScreen)"
