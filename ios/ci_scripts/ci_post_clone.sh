#!/bin/sh
set -e

# Install Flutter via Homebrew (Xcode Cloud does not include Flutter)
export HOMEBREW_NO_AUTO_UPDATE=1
brew install flutter

# Get Flutter packages from the repo root
cd "$CI_WORKSPACE"
flutter pub get

# Bake Mapbox into the Flutter iOS config when the token is set in Xcode Cloud
if [ -n "${MAPBOX_ACCESS_TOKEN:-}" ]; then
  flutter build ios --config-only --release \
    --dart-define="MAPBOX_ACCESS_TOKEN=${MAPBOX_ACCESS_TOKEN}"
fi

# Run CocoaPods to generate the .xcfilelist files Xcode needs
cd ios
pod install --repo-update
