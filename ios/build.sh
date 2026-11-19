#!/bin/bash
# Builds Cart Life for iPhone and iPad as an unsigned .ipa (for LiveContainer,
# AltStore, SideStore or Sideloadly, which sign it themselves).
#
# Runs on macOS with Xcode. It takes the compiled game from
# cartlife/Compiled/Compiled.rar, the AGS engine (Adventure Game Studio) at
# $AGS_TAG with its iOS project, applies ags-touchpad.patch (on-screen arrows,
# Enter, Space and a keyboard button, since the game is played with the
# keyboard) and packs everything into dist/cartlife-<version>.ipa.
#
#   ios/build.sh [version]
#
# Needs: Xcode, unar (brew install unar), ruby with the xcodeproj gem.
set -euo pipefail

VERSION=${1:-1.0}
AGS_TAG=${AGS_TAG:-v3.6.3.17}
BUNDLE_ID=${BUNDLE_ID:-io.github.crazyquark.cartlife}

here=$(cd "$(dirname "$0")" && pwd)
root=$(dirname "$here")
work=$root/build/ios
mkdir -p "$work" "$root/dist"

# 1. The compiled game (the .exe holds the main data, .001/.002 the sprites).
game=$work/game
if [[ ! -f $game/cartlife.002 ]]; then
  mkdir -p "$game"
  unar -q -f -D -o "$game" "$root/cartlife/Compiled/Compiled.rar" \
    cartlife.exe cartlife.001 cartlife.002 audio.vox speech.vox
fi

# 2. The engine, patched.
ags=$work/ags
if [[ ! -d $ags ]]; then
  git clone -q --depth 1 -b "$AGS_TAG" https://github.com/adventuregamestudio/ags "$ags"
  git -C "$ags" apply "$here/ags-touchpad.patch"
  (cd "$ags/libsrc" && ./download.sh >/dev/null)
  ruby "$here/add_touchpad.rb" "$ags/iOS/xcode/ags/AGS.xcodeproj"
  # The app links SDL2.framework, so Xcode's implicit dependencies also pull
  # in SDL's macOS "Framework" target, which writes the same SDL2.framework
  # as the explicit "Framework-iOS" dependency. Build only the explicit chain.
  sed -i '' 's/buildImplicitDependencies = "YES"/buildImplicitDependencies = "NO"/' \
    "$ags/iOS/xcode/ags/AGS.xcodeproj/xcshareddata/xcschemes/AGS Game.xcscheme"
fi

# 3. Game files where the Xcode project expects them, settings and icon.
res=$ags/iOS/Resources
cp "$game/cartlife.exe" "$res/game.ags"
cp "$game/audio.vox" "$game/speech.vox" "$res/"
printf '[misc]\ndatafile=game.ags\n' > "$res/acsetup.cfg"
cp "$here/ios.cfg" "$ags/iOS/misc/ios.cfg"
icons=$ags/iOS/xcode/ags/AGS/Assets.xcassets/AppIcon.appiconset
cp "$here/AppIcon.png" "$icons/AppIcon.png"
cat > "$icons/Contents.json" <<'EOF'
{
  "images" : [ { "filename" : "AppIcon.png", "idiom" : "universal", "platform" : "ios", "size" : "1024x1024" } ],
  "info" : { "author" : "xcode", "version" : 1 }
}
EOF

# 4. Build for devices, unsigned.
dd=$work/DerivedData
xcodebuild -project "$ags/iOS/xcode/ags/AGS.xcodeproj" -scheme "AGS Game" \
  -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' \
  -derivedDataPath "$dd" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= \
  build | grep -E "^(\*\*|error|.*error:|.*warning: .*touchpad)" || true

app="$dd/Build/Products/Release-iphoneos/AGS Game.app"
[[ -f $app/Info.plist ]] || { echo "build failed"; exit 1; }

# 5. The sprite volumes aren't in the Xcode project: add them to the bundle.
cp "$game/cartlife.001" "$game/cartlife.002" "$app/"
# Identity on the app only (on the command line it would also reach the
# embedded frameworks, and iOS refuses duplicate bundle IDs).
plist() { /usr/libexec/PlistBuddy -c "Set :$1 $3" "$app/Info.plist" 2>/dev/null ||
          /usr/libexec/PlistBuddy -c "Add :$1 $2 $3" "$app/Info.plist"; }
plist CFBundleIdentifier string "$BUNDLE_ID"
plist CFBundleDisplayName string "Cart Life"
plist CFBundleName string "Cart Life"
plist CFBundleShortVersionString string "$VERSION"
plist LSApplicationCategoryType string public.app-category.simulation-games
/usr/libexec/PlistBuddy -c "Add :UIFileSharingEnabled bool true" "$app/Info.plist" 2>/dev/null || true

# 6. Pack.
out=$root/dist/cartlife-$VERSION.ipa
stage=$work/ipa
rm -rf "$stage" "$out"
mkdir -p "$stage/Payload"
cp -R "$app" "$stage/Payload/CartLife.app"
(cd "$stage" && zip -qry "$out" Payload)
ls -la "$out"
