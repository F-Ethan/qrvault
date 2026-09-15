#!/bin/sh
set -e

# Xcode Cloud runs this from ios/ci_scripts/. Flutter's `build ios` also
# changes into ios/, so never `cd ios` relative to the current directory.
# CI_WORKSPACE is not always the git root; CI_PRIMARY_REPOSITORY_PATH is.
REPO_ROOT="${CI_PRIMARY_REPOSITORY_PATH:-${CI_WORKSPACE:-}}"
if [ -z "$REPO_ROOT" ] || [ ! -f "$REPO_ROOT/pubspec.yaml" ]; then
  REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
fi

export HOMEBREW_NO_AUTO_UPDATE=1
brew install flutter

cd "$REPO_ROOT"
flutter pub get

# Bake Mapbox into the Flutter iOS config when the token is set in Xcode Cloud
if [ -n "${MAPBOX_ACCESS_TOKEN:-}" ]; then
  flutter build ios --config-only --release \
    --dart-define="MAPBOX_ACCESS_TOKEN=${MAPBOX_ACCESS_TOKEN}"
fi

cd "$REPO_ROOT/ios"
pod install --repo-update
