/// Pure rules for when a full-screen interstitial may appear.
/// Never on camera — callers only invoke this after leaving a full-screen
/// flow (create, scan, detail, map).
bool shouldShowInterstitial({
  required bool optedOut,
  required bool sdkReady,
  required bool adReady,
  required int fullScreenExits,
  required DateTime? lastShownAt,
  required DateTime now,
}) {
  if (optedOut || !sdkReady || !adReady) return false;
  if (fullScreenExits < 2) return false;
  if (lastShownAt != null &&
      now.difference(lastShownAt) < const Duration(minutes: 3)) {
    return false;
  }
  return true;
}

bool isAdsFullScreenRoute(String? name) {
  return name == 'create' ||
      name == 'scan' ||
      name == 'scan-result' ||
      name == 'detail' ||
      name == 'map' ||
      name == '/create' ||
      name == '/scan' ||
      name == '/scan/result' ||
      name == '/map' ||
      (name != null && name.startsWith('/detail/'));
}

/// Do not show an ad when popping scan result back onto the camera.
bool shouldSkipAdForPop({
  required String? poppedName,
  required String? previousName,
}) {
  if (!isAdsFullScreenRoute(poppedName)) return true;
  final backToScan = previousName == 'scan' || previousName == '/scan';
  final fromResult =
      poppedName == 'scan-result' || poppedName == '/scan/result';
  if (fromResult && backToScan) return true;
  return false;
}

bool unlocksRemoveAds({
  required String productId,
  required String incomingProductId,
  required bool isPurchasedOrRestored,
}) {
  return isPurchasedOrRestored && incomingProductId == productId;
}
