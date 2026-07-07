#!/usr/bin/env bash
# make-appdir.sh — assemble engine/release/fteqw-sdl2 into a self-contained
# FTEQW.AppDir: the standard AppImage tree (AppRun + .desktop + icon), with the
# engine's dynamic dependency closure bundled by linuxdeploy and rpath'd to
# $ORIGIN. Requires build-engine.sh first. Plugins are added by build-plugins.sh;
# the AppImage is packed by build-appimage.sh.
#
# Self-containment rule (see docs/PORTING-LINUX.md): bundle everything the engine
# links EXCEPT the platform ABI (glibc) and the graphics/display driver stack
# (OpenGL, the Vulkan loader, X11/Wayland, libdrm) — those must come from the host
# to match its kernel and GPU. audit_selfcontained enforces exactly that.
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

BIN="$(ls -1 "$ENGINE/release/"fteqw-sdl2* 2>/dev/null | head -1 || true)"
[[ -n "$BIN" && -f "$BIN" ]] || die "engine not built — run build-engine.sh first"

APPID="org.fteqw.fteqw"
log "assembling $APPDIR"
rm -rf "$APPDIR"
mkdir -p "$APPDIR/usr/bin" "$APPDIR/usr/lib" \
         "$APPDIR/usr/share/applications" \
         "$APPDIR/usr/share/icons/hicolor/256x256/apps" \
         "$APPDIR/usr/share/metainfo"

# --- engine binary + AppRun --------------------------------------------------
install -m755 "$BIN" "$APPDIR/usr/bin/fteqw-engine"
install -m755 "$SCRIPT_DIR/AppRun" "$APPDIR/AppRun"

# --- desktop entry (reuse upstream dist/, retarget Exec at our engine) --------
# Upstream's Exec calls `fteqw`; our bundled binary is `fteqw-engine` and AppRun
# is the real entrypoint, so rewrite Exec to fteqw-engine (linuxdeploy/AppImage
# ignore Exec at runtime but desktop-integration menus honour it).
sed 's/^Exec=fteqw/Exec=fteqw-engine/' \
    "$REPO/dist/linux/$APPID.desktop" > "$APPDIR/usr/share/applications/$APPID.desktop"
cp "$APPDIR/usr/share/applications/$APPID.desktop" "$APPDIR/$APPID.desktop"

# --- metainfo (AppStream) ----------------------------------------------------
[[ -f "$REPO/dist/linux/$APPID.metainfo.xml" ]] && \
  cp "$REPO/dist/linux/$APPID.metainfo.xml" "$APPDIR/usr/share/metainfo/$APPID.metainfo.xml"

# --- icon: rasterise upstream SVG -> 256x256 PNG -----------------------------
ICON="$APPDIR/usr/share/icons/hicolor/256x256/apps/$APPID.png"
if have rsvg-convert; then
  rsvg-convert -w 256 -h 256 "$REPO/dist/$APPID.svg" -o "$ICON"
elif have convert; then
  convert -background none -resize 256x256 "$REPO/dist/$APPID.svg" "$ICON"
else
  die "no SVG rasteriser (install librsvg2-bin for rsvg-convert)"
fi
cp "$ICON" "$APPDIR/$APPID.png"
ok "bundle skeleton + desktop/icon/metainfo"

# --- bundle the engine's dynamic dependency closure --------------------------
log "bundling linked dependencies (linuxdeploy)…"
LINUXDEPLOY="$(ensure_tool linuxdeploy "$LINUXDEPLOY_URL")"
"$LINUXDEPLOY" --appdir "$APPDIR" \
  -e "$APPDIR/usr/bin/fteqw-engine" \
  -d "$APPDIR/usr/share/applications/$APPID.desktop" \
  -i "$ICON" >/dev/null

# --- self-containment audit --------------------------------------------------
if bad="$(audit_selfcontained "$APPDIR/usr/bin/fteqw-engine" "$APPDIR/usr/lib/"*.so* 2>/dev/null)"; then
  ok "self-contained: 0 non-allowlisted external refs across $(ls "$APPDIR/usr/lib" 2>/dev/null | wc -l | tr -d ' ') bundled libs"
else
  printf '%s\n' "$bad" >&2
  die "self-containment audit failed: the above resolve outside the AppDir and are not host driver/ABI libs"
fi
log "AppDir ready: $APPDIR  (add plugins with build-plugins.sh, pack with build-appimage.sh)"
