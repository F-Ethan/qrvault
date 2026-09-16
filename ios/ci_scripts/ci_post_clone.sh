#!/bin/sh
set -e

# Xcode Cloud runs this from ios/ci_scripts/.
# CI_WORKSPACE is not always the git root; CI_PRIMARY_REPOSITORY_PATH is.
REPO_ROOT="${CI_PRIMARY_REPOSITORY_PATH:-${CI_WORKSPACE:-}}"
if [ -z "$REPO_ROOT" ] || [ ! -f "$REPO_ROOT/pubspec.yaml" ]; then
  REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
fi

# Install the full Flutter SDK (not Homebrew). Homebrew's flutter package
# is incomplete, so archive's Run Script (xcode_backend.sh) exits 65.
# https://docs.flutter.dev/deployment/cd#xcode-cloud
git clone https://github.com/flutter/flutter.git --depth 1 -b stable "$HOME/flutter"
export PATH="$HOME/flutter/bin:$PATH"
flutter precache --ios

cd "$REPO_ROOT"
flutter pub get

# Writes Generated.xcconfig with this builder's FLUTTER_ROOT and dart-defines.
if [ -n "${MAPBOX_ACCESS_TOKEN:-}" ]; then
  flutter build ios --config-only --release \
    --dart-define="MAPBOX_ACCESS_TOKEN=${MAPBOX_ACCESS_TOKEN}"
else
  flutter build ios --config-only --release
fi

export HOMEBREW_NO_AUTO_UPDATE=1
brew install cocoapods

cd "$REPO_ROOT/ios"
pod install --repo-update
