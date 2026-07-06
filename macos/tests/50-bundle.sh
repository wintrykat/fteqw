# 50-bundle.sh — the .app is well-formed and fully self-contained.
section "App bundle & self-containment"

# Structure
check    "Info.plist is valid"          plutil -lint "$APP/Contents/Info.plist"
check    "launcher (CFBundleExecutable) exists" test -f "$MACOS/FTEQW"
contains "launcher is a shell script"   "shell script" "$(file -b "$MACOS/FTEQW" 2>/dev/null)"
contains "engine is a Mach-O"           "Mach-O"       "$(file -b "$MACOS/fteqw-engine" 2>/dev/null)"
# Case-insensitive-FS guard: the two must differ by more than case.
check    "launcher and engine are distinct files" test "$(basename "$MACOS/FTEQW")" '!=' fteqw-engine

# SDL2-compat's SDL3 must be co-located for its @loader_path dlopen to resolve.
check    "SDL3 co-located with the SDL2 shim" test -f "$FW/libSDL3.dylib"

# Definitive self-containment: NO Mach-O in the bundle references Homebrew/usr-local.
ext=0
for f in "$MACOS/fteqw-engine" "$FW"/*.dylib "$RES"/*.so; do
  n="$(otool -L "$f" 2>/dev/null | tail -n +2 | grep -c '/opt/homebrew\|/usr/local' || true)"
  ext=$(( ext + n ))
done
contains "no bundled Mach-O references Homebrew" "0" "$ext"

# Runtime confirmation: launch and prove nothing loads from Homebrew.
if (( HAVE_DATA )); then
  "$ENGINE_BIN" -basedir "$FTEQW_DATA" +set vid_renderer vk \
      +set vid_fullscreen 0 +map start >/dev/null 2>&1 &
  pid=$!; sleep 5
  hb="$(lsof -p "$pid" 2>/dev/null | grep -c '/opt/homebrew' || true)"
  kill -9 "$pid" 2>/dev/null
  contains "no Homebrew dylib is loaded at runtime" "0" "${hb:-0}"
else
  skip "runtime self-containment (lsof)" "needs a display + Quake data (id1)"
fi
