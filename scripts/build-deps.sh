#!/usr/bin/env bash
# Cross-compiles EasyRPG Player's dependencies for PS4 into $OPENORBIS/usr.
# Run scripts/build-toolchain.sh first.
set -euo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"
SRC="${SRC:-$HOME/ps4-src}"
export OPENORBIS="${OPENORBIS:-/opt/pacbrew/ps4/openorbis}"
source "$OPENORBIS/ps4vars.sh"
D="$SRC/deps"
P="$OPENORBIS/usr"
LOG=/tmp/ps4-deps-logs
mkdir -p "$D" "$LOG"

clone() { # url dir commit
  [ -d "$D/$2" ] || git clone -q "$1" "$D/$2"
  git -C "$D/$2" fetch -q --tags 2>/dev/null || true
  git -C "$D/$2" checkout -q "$3"
}
clone https://github.com/madler/zlib zlib 617e19a81f38
clone https://github.com/libarchive/bzip2 bzip2 1ea1ac188ad4
clone https://github.com/pnggroup/libpng libpng 73a6865278d3
clone https://github.com/freetype/freetype freetype 504159f2735e
clone https://github.com/xiph/ogg ogg 06a5e0262cdc
clone https://github.com/xiph/vorbis vorbis 1b75110b5a27
clone https://github.com/libsndfile/libsamplerate libsamplerate 0844c208f683
clone https://github.com/xiph/speexdsp speexdsp 7a158783df74
clone https://github.com/fmtlib/fmt fmt 10.2.1
clone https://github.com/libexpat/libexpat libexpat 0d6dacce2895
clone https://github.com/libsdl-org/mpg123 mpg123 b6881556a0ee
clone https://github.com/aseprite/pixman pixman 285b9a907caf
clone https://github.com/benhoyt/inih inih 18d8e283993c
clone https://github.com/PacBrew/SDL SDL2 bf797a5315c7
git -C "$D/SDL2" apply --check "$HERE/patches/sdl2-pacbrew-newer-clang.patch" 2>/dev/null \
  && git -C "$D/SDL2" apply "$HERE/patches/sdl2-pacbrew-newer-clang.patch" || true

cm() { # cmake build: name srcdir [extra args...]
  local name=$1 src=$2; shift 2
  echo ">>> $name"
  rm -rf "$src/build-ps4" && mkdir -p "$src/build-ps4" && cd "$src/build-ps4"
  openorbis-cmake -G Ninja -DCMAKE_INSTALL_PREFIX="$P" -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_SHARED_LIBS=OFF -DCMAKE_POLICY_VERSION_MINIMUM=3.5 "$@" .. > "$LOG/$name-cfg.log" 2>&1 \
    || { echo "configure failed: $name (see $LOG/$name-cfg.log)"; exit 1; }
  ninja > "$LOG/$name-build.log" 2>&1 || { echo "build failed: $name (see $LOG/$name-build.log)"; exit 1; }
  ninja install > "$LOG/$name-install.log" 2>&1
}

cm zlib "$D/zlib" -DZLIB_BUILD_EXAMPLES=OFF -DZLIB_BUILD_SHARED=OFF -DZLIB_BUILD_TESTING=OFF
rm -f "$P"/lib/libz.so*; [ -f "$P/lib/libz.a" ] || cp "$P/lib/libzlibstatic.a" "$P/lib/libz.a"

echo ">>> bzip2"
cd "$D/bzip2"
[ -f bz_version.h ] || sed "s/@BZ_VERSION@/1.0.8/" bz_version.h.in > bz_version.h
for f in blocksort huffman crctable randtable compress decompress bzlib; do
  $CC $CFLAGS -D_FILE_OFFSET_BITS=64 -c $f.c -o $f.o
done
$AR rcs "$P/lib/libbz2.a" blocksort.o huffman.o crctable.o randtable.o compress.o decompress.o bzlib.o
cp bzlib.h "$P/include/"

cm libpng "$D/libpng" -DPNG_SHARED=OFF -DPNG_TESTS=OFF -DPNG_TOOLS=OFF -DPNG_EXECUTABLES=OFF -DZLIB_ROOT="$P"
cm freetype "$D/freetype" -DFT_DISABLE_HARFBUZZ=ON -DFT_DISABLE_BROTLI=ON -DFT_REQUIRE_ZLIB=ON -DFT_REQUIRE_PNG=ON -DFT_REQUIRE_BZIP2=ON
cm ogg "$D/ogg" -DINSTALL_DOCS=OFF -DBUILD_TESTING=OFF
cm vorbis "$D/vorbis" -DBUILD_TESTING=OFF
cm libsamplerate "$D/libsamplerate" -DBUILD_TESTING=OFF -DLIBSAMPLERATE_EXAMPLES=OFF -DLIBSAMPLERATE_INSTALL=ON

echo ">>> speexdsp"
cd "$D/speexdsp"
[ -f configure ] || ./autogen.sh > "$LOG/speexdsp-autogen.log" 2>&1
./configure --host=x86_64-pc-freebsd --prefix="$P" --disable-shared --enable-static --disable-examples > "$LOG/speexdsp-cfg.log" 2>&1
make -j"$(nproc)" > "$LOG/speexdsp-build.log" 2>&1 && make install > "$LOG/speexdsp-install.log" 2>&1

cm fmt "$D/fmt" -DFMT_TEST=OFF -DFMT_DOC=OFF
CFLAGS="$CFLAGS -DXML_POOR_ENTROPY" cm expat "$D/libexpat/expat" -DEXPAT_BUILD_TOOLS=OFF \
  -DEXPAT_BUILD_EXAMPLES=OFF -DEXPAT_BUILD_TESTS=OFF -DEXPAT_BUILD_DOCS=OFF -DEXPAT_SHARED_LIBS=OFF
cm mpg123 "$D/mpg123/ports/cmake" -DBUILD_PROGRAMS=OFF -DBUILD_LIBOUT123=OFF
cm SDL2 "$D/SDL2"

echo ">>> pixman (plain compile, SSE2/SSSE3)"
cd "$D/pixman/pixman"
sed -e 's/@PIXMAN_VERSION_MAJOR@/0/;s/@PIXMAN_VERSION_MINOR@/40/;s/@PIXMAN_VERSION_MICRO@/1/' pixman-version.h.in > pixman-version.h
cat > config.h <<'EOF'
#define PACKAGE "pixman"
#define HAVE_PTHREADS 1
#define USE_SSE2 1
#define USE_SSSE3 1
#define HAVE_BUILTIN_CLZ 1
#define HAVE_GCC_VECTOR_EXTENSIONS 1
#define HAVE_POSIX_MEMALIGN 1
#define SIZEOF_LONG 8
EOF
rm -f ./*.o
for f in pixman pixman-access pixman-access-accessors pixman-bits-image pixman-combine32 pixman-combine-float \
         pixman-conical-gradient pixman-filter pixman-x86 pixman-mips pixman-arm pixman-ppc pixman-edge \
         pixman-edge-accessors pixman-fast-path pixman-glyph pixman-general pixman-gradient-walker pixman-image \
         pixman-implementation pixman-linear-gradient pixman-matrix pixman-noop pixman-radial-gradient \
         pixman-region16 pixman-region32 pixman-solid-fill pixman-timer pixman-trap pixman-utils; do
  $CC $CFLAGS -DHAVE_CONFIG_H -I. -w -c $f.c -o $f.o
done
$CC $CFLAGS -DHAVE_CONFIG_H -I. -w -msse2 -c pixman-sse2.c -o pixman-sse2.o
$CC $CFLAGS -DHAVE_CONFIG_H -I. -w -mssse3 -c pixman-ssse3.c -o pixman-ssse3.o
rm -f "$P/lib/libpixman-1.a"; $AR rcs "$P/lib/libpixman-1.a" ./*.o
mkdir -p "$P/include/pixman-1" && cp pixman.h pixman-version.h "$P/include/pixman-1/"
cat > "$P/lib/pkgconfig/pixman-1.pc" <<EOF
prefix=$P
libdir=\${prefix}/lib
includedir=\${prefix}/include
Name: Pixman
Description: The pixman library (version 1)
Version: 0.40.1
Cflags: -I\${includedir}/pixman-1
Libs: -L\${libdir} -lpixman-1
EOF

echo ">>> inih"
cd "$D/inih"
$CC $CFLAGS -c ini.c -o ini.o && $AR rcs "$P/lib/libinih.a" ini.o && cp ini.h "$P/include/"
printf "prefix=%s\nlibdir=\${prefix}/lib\nincludedir=\${prefix}/include\nName: inih\nDescription: inih\nVersion: 58\nCflags: -I\${includedir}\nLibs: -L\${libdir} -linih\n" "$P" > "$P/lib/pkgconfig/inih.pc"

echo ">>> ICU 78.3 (text encodings: Shift-JIS, Windows-125x, GBK, Big5, EUC-KR ...)"
if [ ! -d "$SRC/icu" ]; then
  git clone -q --depth 1 --filter=blob:none --sparse -b release-78.3 https://github.com/unicode-org/icu "$SRC/icu"
  git -C "$SRC/icu" sparse-checkout set icu4c/source
fi
ICUS="$SRC/icu/icu4c/source"
chmod u+x "$ICUS/configure"
cp "$ICUS/config/mh-linux" "$ICUS/config/mh-unknown"
grep -q UCONFIG_ONLY_COLLATION "$ICUS/config/mh-unknown" || perl -pi -e 's/^LIBCPPFLAGS =/LIBCPPFLAGS = -DUCONFIG_ONLY_COLLATION/' "$ICUS/config/mh-unknown"
perl -pi -e 's/SMALL_BUFFER_MAX_SIZE 512/SMALL_BUFFER_MAX_SIZE 2048/' "$ICUS/tools/toolutil/pkg_genc.h"
export ICU_DATA_FILTER_FILE="$HERE/scripts/icu-filter.json"   # only converters (+aliases, normalization): ~5 MB
ICU_ARGS=(--enable-static --disable-shared --enable-strict=no --disable-tests --disable-samples --disable-dyload
          --disable-extras --disable-icuio --with-data-packaging=static --disable-layout --disable-layoutex --enable-draft=no)
mkdir -p "$SRC/icu-native" && (cd "$SRC/icu-native" && \
  env -u CFLAGS -u CXXFLAGS -u CPPFLAGS -u LDFLAGS -u LIBS CC=clang CXX=clang++ "$ICUS/configure" "${ICU_ARGS[@]}" > "$LOG/icu-native-cfg.log" && \
  env -u CFLAGS -u CXXFLAGS -u CPPFLAGS -u LDFLAGS -u LIBS make -j"$(nproc)" > "$LOG/icu-native-build.log")
mkdir -p "$SRC/icu-cross" && (cd "$SRC/icu-cross" && \
  "$ICUS/configure" "${ICU_ARGS[@]}" --prefix="$P" --host=x86_64-none-elf --with-cross-build="$SRC/icu-native" --disable-tools > "$LOG/icu-cross-cfg.log" && \
  make -j"$(nproc)" > "$LOG/icu-cross-build.log" && make install > "$LOG/icu-cross-install.log")
unset ICU_DATA_FILTER_FILE

echo "Dependencies ready in $P"
