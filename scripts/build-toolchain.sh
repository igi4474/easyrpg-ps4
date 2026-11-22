#!/usr/bin/env bash
# Builds a PS4 (OpenOrbis/PacBrew-layout) toolchain entirely from source, using the
# host's clang/lld (tested with clang 18 on Ubuntu 24.04). Installs to $OPENORBIS
# (default /opt/pacbrew/ps4/openorbis). Needs: clang, lld, llvm tools, cmake, ninja,
# make, git, go, python3, pkg-config.
#
# Why from source: it was built in an environment without access to release downloads.
# If you can download the official OpenOrbis release, you can use that instead, but you
# STILL need patches/musl-ps4-pthread-types.patch (see docs/NOTES.md).
set -euo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"
SRC="${SRC:-$HOME/ps4-src}"
export OPENORBIS="${OPENORBIS:-/opt/pacbrew/ps4/openorbis}"
OO="$OPENORBIS"
mkdir -p "$SRC" "$OO"/{bin,lib,cmake,usr/lib/pkgconfig,usr/include,usr/bin}

clone() { # url dir commit
  [ -d "$SRC/$2" ] || git clone -q "$1" "$SRC/$2"
  git -C "$SRC/$2" checkout -q "$3"
}

echo ">>> host tools"
for t in clang clang++ ld.lld llvm-ar llvm-ranlib llvm-nm llvm-objcopy llvm-strip; do
  ln -sf "$(command -v $t)" "$OO/bin/$t"
done

echo ">>> sources"
clone https://github.com/OpenOrbis/OpenOrbis-PS4-Toolchain oo 0a1aaf9dd4a9
clone https://github.com/PacBrew/ps4-openorbis ps4-openorbis 16f27e38760e
clone https://github.com/PacBrew/ps4-openorbis-musl musl 140a653299ff
clone https://github.com/OpenOrbis/orbis-lib-gen orbis-lib-gen 8443a656ba40
clone https://github.com/OpenOrbis/create-fself create-fself f2da6229684c
clone https://github.com/OpenOrbis/create-gp4 create-gp4 bf8e66e9e9bd
[ -d "$SRC/ps4libdoc" ] || git clone -q --depth 1 -b 5.05 https://github.com/idc/ps4libdoc "$SRC/ps4libdoc"
if [ ! -d "$SRC/llvm12" ]; then
  git clone -q --depth 1 --filter=blob:none --sparse -b llvmorg-12.0.1 https://github.com/llvm/llvm-project "$SRC/llvm12"
  git -C "$SRC/llvm12" sparse-checkout set compiler-rt libunwind libcxxabi libcxx llvm/cmake llvm/utils/llvm-lit
  (cd "$SRC/llvm12" && patch -Np2 -i "$SRC/ps4-openorbis/libcxx/001-ps4.patch")
fi

echo ">>> headers, link script, helper files"
cp -r "$SRC/oo/include" "$SRC/oo/link.x" "$SRC/oo/samples" "$OO/"
# OpenOrbis bundles very old FreeType headers that shadow the real FreeType; move them away.
[ -d "$OO/include/freetype" ] && mv "$OO/include/freetype" "$OO/include/freetype.oo-old"
[ -f "$OO/include/ft2build.h" ] && mv "$OO/include/ft2build.h" "$OO/include/ft2build.h.oo-old"
clang -c -o "$OO/lib/crtlib.o" "$SRC/oo/src/crt/crtlib.c"
cp "$SRC/ps4-openorbis/vars/ps4.cmake" "$OO/cmake/"
cp "$SRC/ps4-openorbis/vars/ps4vars.sh" "$OO/"
# libc++ headers must come BEFORE the C headers, otherwise <cmath> breaks.
sed -i 's#^export CXXFLAGS="${CFLAGS} -isystem ${OPENORBIS}/include/c++/v1"#export CXXFLAGS="-isystem ${OPENORBIS}/include/c++/v1 ${CFLAGS}"#; s#^export CPPFLAGS="${CFLAGS} -isystem ${OPENORBIS}/include/c++/v1"#export CPPFLAGS="${CFLAGS}"#' "$OO/ps4vars.sh"
install -m755 "$SRC/ps4-openorbis/vars/openorbis-cmake" "$OO/usr/bin/"
install -m755 "$SRC/ps4-openorbis/pkg-config/pkg-config.in" "$OO/usr/bin/openorbis-pkg-config"
cp "$SRC/ps4-openorbis/orbis-lib-gen/libSceLibcInternal.so" "$OO/lib/"

echo ">>> musl (with PS4 pthread type fix)"
cd "$SRC/musl"
git apply --check "$HERE/patches/musl-ps4-pthread-types.patch" 2>/dev/null && git apply "$HERE/patches/musl-ps4-pthread-types.patch" || true
./configure --target=x86_64-scei-ps4 --prefix="$OO" --disable-shared CC="$OO/bin/clang" \
  CFLAGS="-fPIC -DPS4 -D_LIBUNWIND_IS_BAREMETAL=1 -DPS4_FLEXIBLE_MEMORY=1" > /dev/null
make --quiet -j"$(nproc)" && make install > /dev/null

echo ">>> sys/endian.h shim (FreeBSD header some libraries expect, e.g. ICU)"
cat > "$OO/include/sys/endian.h" <<'EOF2'
/* PS4 shim: FreeBSD-style <sys/endian.h> on top of musl's <endian.h> */
#ifndef _PS4_SYS_ENDIAN_H
#define _PS4_SYS_ENDIAN_H
#include <endian.h>
#ifndef _BYTE_ORDER
#define _BYTE_ORDER __BYTE_ORDER
#define _LITTLE_ENDIAN __LITTLE_ENDIAN
#define _BIG_ENDIAN __BIG_ENDIAN
#endif
#endif
EOF2

echo ">>> system library stubs"
rm -rf /tmp/libdoc && mkdir /tmp/libdoc
find "$SRC/ps4libdoc" -name "*.json" -exec cp {} /tmp/libdoc/ \;
cd "$SRC/orbis-lib-gen" && rm -rf build && mkdir build && python3 generate.py /tmp/libdoc > /dev/null
cd build
for c in *.c; do
  b="${c%.c}"
  case "$b" in libc|libSceLibcInternal) continue;; esac   # libc = musl (static); keep PacBrew's stripped LibcInternal
  clang -ffreestanding -nostdlib -fno-builtin -fPIC -shared -w -o "$OO/lib/$b.so" "$c"
done

echo ">>> compiler-rt builtins"
rm -rf /tmp/rtb && mkdir /tmp/rtb
cd "$SRC/llvm12/compiler-rt/lib/builtins"
for f in x86_64/*.c x86_64/*.S *.c; do
  b="$(basename "$f")"; b="${b%.*}"
  [ -e "/tmp/rtb/$b.o" ] && continue
  case "$b" in emutls|enable_execute_stack|clear_cache|gcc_personality_v0|atomic|os_version_check|trampoline_setup) continue;; esac
  clang -c -O2 -fPIC -fno-builtin -D__PS4__ -w -I. "$f" -o "/tmp/rtb/$b.o" || true
done
llvm-ar rcs "$OO/lib/libclang_rt.builtins-x86_64.a" /tmp/rtb/*.o

echo ">>> libunwind / libc++abi / libc++"
# A stub llvm-config is enough for these standalone runtime builds.
cat > /tmp/fake-llvm-config <<'EOF'
#!/bin/sh
for a in "$@"; do case "$a" in
--obj-root) echo /tmp/fakellvm;; --bindir) echo /usr/bin;; --libdir) echo /tmp/fakellvm/lib;;
--includedir) echo /tmp/fakellvm/include;; --cmakedir) echo /tmp/fakellvm/cmake;; --version) echo 12.0.1;; esac; done
EOF
chmod +x /tmp/fake-llvm-config
COMMON=(-DLLVM_CONFIG_PATH=/tmp/fake-llvm-config -DCMAKE_C_COMPILER="$OO/bin/clang" -DCMAKE_CXX_COMPILER="$OO/bin/clang++"
        -DLLVM_PATH=../../llvm -DCMAKE_INSTALL_PREFIX="$OO")
cd "$SRC/llvm12/libunwind" && rm -rf build && mkdir build && cd build
cmake "${COMMON[@]}" -DCMAKE_C_FLAGS="-fPIC -D__PS4__ -D_LIBUNWIND_IS_BAREMETAL=1" -DCMAKE_CXX_FLAGS="-fPIC -D__PS4__ -D_LIBUNWIND_IS_BAREMETAL=1" \
  -DLIBUNWIND_USE_COMPILER_RT=YES -DLIBUNWIND_ENABLE_STATIC=ON -DLIBUNWIND_ENABLE_SHARED=OFF -DLIBUNWIND_SYSROOT="$OO" .. > /dev/null
make -j"$(nproc)" > /dev/null && make install > /dev/null
cd "$SRC/llvm12/libcxxabi" && rm -rf build && mkdir build && cd build
cmake "${COMMON[@]}" -DCMAKE_C_FLAGS="-fPIC -D__PS4__ -D_LIBUNWIND_IS_BAREMETAL=1 -I$OO/usr/include" -DCMAKE_CXX_FLAGS="-fPIC -D__PS4__ -D_LIBUNWIND_IS_BAREMETAL=1 -I$OO/usr/include" \
  -DLIBCXXABI_ENABLE_SHARED=NO -DLIBCXXABI_ENABLE_STATIC=YES -DLIBCXXABI_ENABLE_EXCEPTIONS=YES -DLIBCXXABI_USE_COMPILER_RT=YES \
  -DLIBCXXABI_USE_LLVM_UNWINDER=YES -DLIBCXXABI_ENABLE_PIC=YES -DLIBCXXABI_LIBUNWIND_PATH=../../libunwind \
  -DLIBCXXABI_LIBCXX_INCLUDES=../../libcxx/include -DLIBCXXABI_SYSROOT="$OO" .. > /dev/null
make -j"$(nproc)" > /dev/null && make install > /dev/null
cd "$SRC/llvm12/libcxx" && rm -rf build && mkdir build && cd build
cmake "${COMMON[@]}" -DCMAKE_C_FLAGS="-fPIC -D__PS4__" -DCMAKE_CXX_FLAGS="-fPIC -D__PS4__" \
  -DLIBCXX_ENABLE_RTTI=YES -DLIBCXX_HAS_MUSL_LIBC=1 -DLIBCXX_HAS_GCC_S_LIB=0 -DLIBCXX_ENABLE_SHARED=NO \
  -DLIBCXX_ENABLE_THREADS=1 -DLIBCXX_HAS_THREAD_API_PTHREAD=1 -DLIBCXX_CXX_ABI=libcxxabi \
  -DLIBCXX_CXX_ABI_INCLUDE_PATHS=../../libcxxabi/include -DLIBCXX_CXX_ABI_LIBRARY_PATH=../../libcxxabi/build/lib \
  -DLIBCXX_ENABLE_STATIC_ABI_LIBRARY=ON -DLIBCXX_SYSROOT="$OO" .. > /dev/null
make -j"$(nproc)" > /dev/null && make install > /dev/null
cd "$OO/lib"
printf "CREATE libc++M.a\nADDLIB libunwind.a\nADDLIB libc++abi.a\nADDLIB libc++.a\nSAVE\nEND\n" | llvm-ar -M
mv libc++M.a libc++.a

echo ">>> create-fself / create-gp4 (Go, no network needed)"
cd "$SRC/create-fself/cmd/create-fself"
sed -i 's#=> .*fself$#=> ../../pkg/fself#; s#=> .*oelf$#=> ../../pkg/oelf#' go.mod
GOPROXY=off GOFLAGS=-mod=mod go build -o "$OO/bin/create-fself" .
cd "$SRC/create-gp4/cmd/create-gp4" && GOPROXY=off go build -o "$OO/bin/create-gp4" .

echo "Toolchain ready in $OO"
