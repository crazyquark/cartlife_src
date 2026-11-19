#!/bin/bash
# Builds Cart Life for Linux and the Steam Deck as an AppImage.
#
# Takes the compiled game from cartlife/Compiled/Compiled.rar and the AGS
# engine (Adventure Game Studio) at $AGS_TAG, applies ags-gamepad.patch
# (controller -> arrow keys, cursor and clicks, since the game only reads
# the keyboard and mouse) and packs both into
# dist/cartlife-<version>-<arch>.AppImage.
#
#   linux/build.sh [version]
#
# Needs: cmake, ninja, a C++ compiler, unar, the SDL2 build dependencies
# (X11, Wayland, ALSA, PulseAudio, udev headers) and curl.
set -euo pipefail

VERSION=${1:-1.0}
AGS_TAG=${AGS_TAG:-v3.6.3.17}
ARCH=$(uname -m)

here=$(cd "$(dirname "$0")" && pwd)
root=$(dirname "$here")
work=$root/build/linux
mkdir -p "$work" "$root/dist"

# 1. The compiled game (the .exe holds the main data, .001/.002 the sprites).
game=$work/game
if [[ ! -f $game/cartlife.002 ]]; then
  mkdir -p "$game"
  unar -q -f -D -o "$game" "$root/cartlife/Compiled/Compiled.rar" \
    cartlife.exe cartlife.001 cartlife.002 audio.vox speech.vox
fi

# 2. The engine, patched, with the C++ runtime linked in.
ags=$work/ags
if [[ ! -d $ags ]]; then
  git clone -q --depth 1 -b "$AGS_TAG" https://github.com/adventuregamestudio/ags "$ags"
  git -C "$ags" apply "$here/ags-gamepad.patch"
fi
cmake -S "$ags" -B "$work/engine" -G Ninja -DCMAKE_BUILD_TYPE=Release \
  -DAGS_BUILD_TOOLS=OFF -DAGS_TESTS=OFF \
  -DCMAKE_EXE_LINKER_FLAGS="-static-libstdc++ -static-libgcc" >/dev/null
ninja -C "$work/engine" ags

# 3. AppDir.
app=$work/AppDir
rm -rf "$app"
mkdir -p "$app/usr/bin" "$app/usr/share/cartlife"
cp "$work/engine/ags" "$app/usr/bin/ags"
strip "$app/usr/bin/ags"
cp "$game"/* "$app/usr/share/cartlife/"
cp "$here/acsetup.cfg" "$app/usr/share/cartlife/"
cp "$here/AppRun" "$app/AppRun"
cp "$here/cartlife.desktop" "$app/cartlife.desktop"
cp "$root/ios/AppIcon.png" "$app/cartlife.png"
ln -s cartlife.png "$app/.DirIcon"

# 4. Pack.
tool=$work/appimagetool-$ARCH.AppImage
if [[ ! -x $tool ]]; then
  curl -sSLo "$tool" "https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-$ARCH.AppImage"
  chmod +x "$tool"
fi
out=$root/dist/cartlife-$VERSION-$ARCH.AppImage
ARCH=$ARCH APPIMAGE_EXTRACT_AND_RUN=1 "$tool" --no-appstream "$app" "$out" >/dev/null
ls -la "$out"
