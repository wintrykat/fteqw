# 10-toolchain.sh — the MSYS2 CLANGARM64 toolchain is present and native-arm64.
# Tier 1 (always runs).
section "Toolchain (MSYS2 CLANGARM64)"

check    "clang present"            command -v clang
check    "make present"            command -v make
check    "llvm binutils present"   command -v llvm-nm
check    "ntldd present (DLL audit)" command -v ntldd
check    "zip present (plugin metadata)" command -v zip

# The compiler must target an aarch64 mingw/windows triple.
contains "clang targets aarch64"   "aarch64" "$(clang -dumpmachine 2>/dev/null)"
contains "clang targets windows"   "windows" "$(clang -dumpmachine 2>/dev/null)"
