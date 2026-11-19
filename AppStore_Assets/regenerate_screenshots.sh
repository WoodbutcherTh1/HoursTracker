#!/bin/bash
# Regenerates the real App Store screenshots end to end:
#   1. Boot/build/run the RealAppStoreScreenshotTests UI test, which drives the actual
#      app in the iOS Simulator and captures Raw_Screenshots/<lang>/{1,2,3}.png.
#   2. Frame those real captures with fastlane `frameit` (device bezel + localized
#      headline) using frameit_config/<lang>/{Framefile.json,title.strings| into
#      Screenshots/<lang>/{1,2,3}.png.
#   3. Re-render the Arabic headline via headless Chrome and composite it over
#      frameit's output, since ImageMagick's text renderer doesn't do Arabic letter
#      joining (frameit_config/arabic/Framefile.json makes its own title transparent
#      for exactly this reason).
#
# Prerequisites: Xcode + a booted iOS Simulator (6.9" device, e.g. iPhone 16 Pro Max,
# for native 1320x2868 output), `brew install fastlane imagemagick`, and
# `fastlane frameit download_frames` run once.
#
# Usage: AppStore_Assets/regenerate_screenshots.sh <SIMULATOR_UDID>
set -euo pipefail

UDID="${1:?Usage: regenerate_screenshots.sh <SIMULATOR_UDID>}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$ROOT/.." && pwd)"
DERIVED_DATA="$(mktemp -d)"

echo "==> Building for testing"
xcodebuild build-for-testing \
  -scheme HoursTracker \
  -destination "platform=iOS Simulator,id=$UDID" \
  -derivedDataPath "$DERIVED_DATA" \
  -project "$REPO/HoursTracker.xcodeproj"

echo "==> Capturing real screenshots (5 languages x 3 screens)"
rm -rf "$ROOT/Raw_Screenshots"
xcodebuild test-without-building \
  -destination "platform=iOS Simulator,id=$UDID" \
  -derivedDataPath "$DERIVED_DATA" \
  -only-testing:HoursTrackerUITests/RealAppStoreScreenshotTests \
  -project "$REPO/HoursTracker.xcodeproj" \
  -scheme HoursTracker

echo "==> Framing with fastlane frameit"
WORK="$(mktemp -d)"
for lang in english hebrew arabic russian thai; do
  mkdir -p "$WORK/$lang"
  cp "$ROOT/Raw_Screenshots/$lang"/*.png "$WORK/$lang/"
  cp "$ROOT/frameit_config/$lang/Framefile.json" "$WORK/$lang/"
  cp "$ROOT/frameit_config/$lang/title.strings" "$WORK/$lang/"
done
( cd "$WORK" && fastlane frameit ios )

echo "==> Compositing properly-shaped Arabic headlines"
"$ROOT/_frame_assets/render_arabic_headlines.sh"
for i in 1 2 3; do
  magick "$WORK/arabic/${i}_framed.png" "$ROOT/_frame_assets/arabic_headlines/h${i}.png" \
    -gravity north -geometry +0+2403 -compose over -composite \
    "$WORK/arabic/${i}_framed.png"
done

echo "==> Publishing to Screenshots/<lang>/"
rm -rf "$ROOT/Screenshots"
for lang in english hebrew arabic russian thai; do
  mkdir -p "$ROOT/Screenshots/$lang"
  for i in 1 2 3; do
    cp "$WORK/$lang/${i}_framed.png" "$ROOT/Screenshots/$lang/${i}.png"
  done
done
rm -rf "$WORK" "$DERIVED_DATA"

echo "==> Done. Verifying sizes:"
for f in "$ROOT"/Screenshots/*/*.png; do
  sips -g pixelWidth -g pixelHeight "$f" | tail -2 | tr '\n' ' '
  echo "<- $f"
done
