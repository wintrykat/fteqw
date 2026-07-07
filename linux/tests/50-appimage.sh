# 50-appimage.sh — the AppDir/AppImage is well-formed and fully self-contained.
section "AppDir & AppImage self-containment"

APPID="org.fteqw.fteqw"

# --- structure ---------------------------------------------------------------
check    "AppRun exists and is executable"  test -x "$APPDIR/AppRun"
check    "top-level .desktop exists"        test -f "$APPDIR/$APPID.desktop"
check    "top-level icon exists"            test -f "$APPDIR/$APPID.png"
contains "AppRun is a shell script"         "shell script" "$(file -b "$APPDIR/AppRun" 2>/dev/null)"
contains "engine is an ELF binary"          "ELF"          "$(file -b "$ENGINE_BIN" 2>/dev/null)"
if command -v desktop-file-validate >/dev/null 2>&1; then
  check  ".desktop passes desktop-file-validate" desktop-file-validate "$APPDIR/$APPID.desktop"
else
  contains ".desktop declares a Game category" "Categories=Game" "$(cat "$APPDIR/$APPID.desktop" 2>/dev/null)"
fi

# --- engine rpath points at the bundled libs --------------------------------
rpath="$(patchelf --print-rpath "$ENGINE_BIN" 2>/dev/null || true)"
contains "engine rpath resolves bundled libs (\$ORIGIN/../lib)" '$ORIGIN' "$rpath"

# --- definitive self-containment: nothing but host driver/ABI libs escape ----
if bad="$(audit_selfcontained "$ENGINE_BIN" "$APPDIR/usr/lib/"*.so* 2>/dev/null)" && [[ -z "$bad" ]]; then
  pass "no bundled ELF references a non-allowlisted external library"
else
  fail "no bundled ELF references a non-allowlisted external library" \
       "$(printf '%s' "$bad" | tr '\n' ' ')"
fi

# --- the packaged AppImage ---------------------------------------------------
if [[ -f "$APPIMAGE" ]]; then
  check "AppImage is executable"          test -x "$APPIMAGE"
  # extract-and-run avoids a FUSE requirement in VM/CI.
  out="$(APPIMAGE_EXTRACT_AND_RUN=1 "$APPIMAGE" -dedicated +quit 2>&1 | head -40 || true)"
  if ((HAVE_DATA)); then
    contains "AppImage runs the engine" "registered version" "$out"
  else
    contains "AppImage runs the engine" "basedir" "$out"
  fi
else
  skip "AppImage is executable" "not packed yet — run build-appimage.sh"
  skip "AppImage runs the engine" "not packed yet — run build-appimage.sh"
fi
