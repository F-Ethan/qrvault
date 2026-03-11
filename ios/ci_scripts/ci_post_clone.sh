#!/bin/sh
set -e

# Install Flutter via Homebrew (Xcode Cloud does not include Flutter)
export HOMEBREW_NO_AUTO_UPDATE=1
brew install flutter

# Get Flutter packages from the repo root
cd "$CI_WORKSPACE"
flutter pub get

# Run CocoaPods to generate the .xcfilelist files Xcode needs
cd ios
pod install --repo-update
