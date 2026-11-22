#!/usr/bin/env bash
# Builds liblcf + EasyRPG Player for PS4 and assembles a package folder (out/EasyRPG)
# ready for tools/build-pkg.bat (LibOrbisPkg PkgTool) on Windows.
# Run build-toolchain.sh and build-deps.sh first.
set -euo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"
SRC="${SRC:-$HOME/ps4-src}"
export OPENORBIS="${OPENORBIS:-/opt/pacbrew/ps4/openorbis}"
source "$OPENORBIS/ps4vars.sh"
P="$OPENORBIS/usr"
OUT="$HERE/out/EasyRPG"

[ -d "$SRC/liblcf" ] || git clone -q https://github.com/EasyRPG/liblcf "$SRC/liblcf"
git -C "$SRC/liblcf" checkout -q 6854310c3432
[ -d "$SRC/Player" ] || git clone -q https://github.com/EasyRPG/Player "$SRC/Player"
git -C "$SRC/Player" checkout -q a99ca834b856
git -C "$SRC/Player" apply --check "$HERE/patches/easyrpg-player-ps4.patch" 2>/dev/null \
  && git -C "$SRC/Player" apply "$HERE/patches/easyrpg-player-ps4.patch" || true

echo ">>> liblcf (no ICU: only Windows-1252 text encoding for now)"
cd "$SRC/liblcf" && rm -rf build-ps4 && mkdir build-ps4 && cd build-ps4
openorbis-cmake -G Ninja -DCMAKE_INSTALL_PREFIX="$P" -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF \
  -DLIBLCF_WITH_ICU=OFF -DLIBLCF_ENABLE_TOOLS=OFF -DLIBLCF_ENABLE_TESTS=OFF -DLIBLCF_UPDATE_MIMEDB=OFF \
  -DLIBLCF_ENABLE_INSTALL=ON .. > /dev/null
ninja > /dev/null && ninja install > /dev/null

echo ">>> EasyRPG Player"
cd "$SRC/Player" && rm -rf build-ps4 && mkdir build-ps4 && cd build-ps4
openorbis-cmake -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
  -DPLAYER_WITH_HARFBUZZ=OFF -DPLAYER_WITH_LHASA=OFF -DPLAYER_WITH_NLOHMANN_JSON=OFF \
  -DPLAYER_WITH_LIBSNDFILE=OFF -DPLAYER_WITH_OPUS=OFF -DPLAYER_WITH_WILDMIDI=OFF \
  -DPLAYER_WITH_FLUIDSYNTH=OFF -DPLAYER_WITH_FLUIDLITE=OFF -DPLAYER_WITH_XMP=OFF -DPLAYER_ENABLE_TESTS=OFF .. > /dev/null
ninja easyrpg-player_self   # PkgTool.Core isn't needed; we pack the .pkg separately

echo ">>> package folder"
rm -rf "$OUT" && mkdir -p "$OUT"
cp -r "$SRC/Player/resources/ps4/"* "$OUT/"
cp eboot.bin "$OUT/"
CID=IV0001-ERPG00001_00-EASYRPGPLAYER000
python3 "$HERE/tools/make_sfo.py" "$OUT/sce_sys/param.sfo" --title "EasyRPG Player (test)" \
  --title-id ERPG00001 --content-id "$CID" --version 01.02
(cd "$OUT" && "$OPENORBIS/bin/create-gp4" -out app.gp4 --content-id "$CID" --path .)
echo "Done: $OUT  (copy it to Windows and run tools/build-pkg.bat next to it)"
