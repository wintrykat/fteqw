#!/bin/zsh
# make-app.sh — assemble engine/release/fteqw-sdl2 into a self-contained,
# ad-hoc-signed FTEQW.app that runs on any Apple Silicon Mac without Homebrew.
# Requires build-engine.sh to have run first. Plugins are added by build-plugins.sh.
source "${0:A:h}/common.sh"

BIN="$ENGINE/release/fteqw-sdl2"
[[ -f "$BIN" ]] || die "engine not built — run build-engine.sh first"
APP="$FTEQW_APP"; FW="$APP/Contents/Frameworks"; RES="$APP/Contents/Resources"; MACOS="$APP/Contents/MacOS"

log "assembling $APP"
rm -rf "$APP"; mkdir -p "$MACOS" "$RES" "$FW"

# --- engine binary + launcher ------------------------------------------------
# NOTE: bundle exe (FTEQW) and engine binary (fteqw-engine) MUST differ by more
# than case — the default macOS volume is case-insensitive.
cp "$BIN" "$MACOS/fteqw-engine"; chmod +x "$MACOS/fteqw-engine"
codesign --force --sign - "$MACOS/fteqw-engine"
cp "${0:A:h}/launcher.sh" "$MACOS/FTEQW"; chmod +x "$MACOS/FTEQW"

# --- Info.plist / PkgInfo ----------------------------------------------------
VER="$(cd "$REPO" && git describe --always --long --dirty 2>/dev/null || echo dev)"
printf 'APPL????' > "$APP/Contents/PkgInfo"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
	<key>CFBundleName</key><string>FTEQW</string>
	<key>CFBundleDisplayName</key><string>FTEQW</string>
	<key>CFBundleIdentifier</key><string>info.fte.fteqw</string>
	<key>CFBundleExecutable</key><string>FTEQW</string>
	<key>CFBundlePackageType</key><string>APPL</string>
	<key>CFBundleVersion</key><string>${VER}</string>
	<key>CFBundleShortVersionString</key><string>${VER}</string>
	<key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
	<key>LSMinimumSystemVersion</key><string>11.0</string>
	<key>NSHighResolutionCapable</key><true/>
	<key>NSPrincipalClass</key><string>NSApplication</string>
	<key>NSSupportsAutomaticGraphicsSwitching</key><true/>
</dict></plist>
PLIST
ok "bundle skeleton + Info.plist ($VER)"

# --- self-contain: linked closure via dylibbundler --------------------------
log "bundling linked dependencies…"
dylibbundler -of -cd -b -x "$MACOS/fteqw-engine" -d "$FW/" -p @executable_path/../Frameworks/ >/dev/null

# --- self-contain: the two dlopen'd libraries dylibbundler can't see ---------
# sdl2-compat dlopen's SDL3 via @loader_path — co-locate it in Frameworks.
cp "$BREW/opt/sdl3/lib/libSDL3.0.dylib" "$FW/libSDL3.dylib"
# MoltenVK is dlopen'd through the launcher's SDL_VULKAN_LIBRARY.
cp "$BREW/lib/libMoltenVK.dylib" "$FW/libMoltenVK.dylib"
chmod u+w "$FW/libSDL3.dylib" "$FW/libMoltenVK.dylib"
install_name_tool -id @rpath/libSDL3.dylib    "$FW/libSDL3.dylib"
install_name_tool -id @rpath/libMoltenVK.dylib "$FW/libMoltenVK.dylib"
ok "added SDL3 + MoltenVK"

# --- re-sign every Mach-O (install_name_tool invalidates signatures) ---------
for f in "$FW"/*.dylib "$MACOS/fteqw-engine"; do codesign --force --sign - "$f"; done

mkdir -p "$FTEQW_DATA"

# --- audit -------------------------------------------------------------------
ext=0
for f in "$MACOS/fteqw-engine" "$FW"/*.dylib; do
  n=$(otool -L "$f" | tail -n +2 | grep -c '/opt/homebrew\|/usr/local' || true); ext=$((ext+n))
done
(( ext == 0 )) || die "self-containment audit failed: $ext external refs remain"
ok "self-contained: 0 external refs across $(ls "$FW" | wc -l | tr -d ' ') bundled dylibs"
log "app ready: $APP  (add plugins with build-plugins.sh)"
