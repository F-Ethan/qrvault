import 'package:flutter_test/flutter_test.dart';
import 'package:qrvault/core/ads/ads_gate.dart';

void main() {
  test('skips ads when opted out or not ready', () {
    expect(
      shouldShowInterstitial(
        optedOut: true,
        sdkReady: true,
        adReady: true,
        fullScreenExits: 5,
        lastShownAt: null,
        now: DateTime(2026, 9, 16),
      ),
      isFalse,
    );
    expect(
      shouldShowInterstitial(
        optedOut: false,
        sdkReady: false,
        adReady: true,
        fullScreenExits: 5,
        lastShownAt: null,
        now: DateTime(2026, 9, 16),
      ),
      isFalse,
    );
  });

  test('skips the first full-screen exit', () {
    expect(
      shouldShowInterstitial(
        optedOut: false,
        sdkReady: true,
        adReady: true,
        fullScreenExits: 1,
        lastShownAt: null,
        now: DateTime(2026, 9, 16),
      ),
      isFalse,
    );
    expect(
      shouldShowInterstitial(
        optedOut: false,
        sdkReady: true,
        adReady: true,
        fullScreenExits: 2,
        lastShownAt: null,
        now: DateTime(2026, 9, 16),
      ),
      isTrue,
    );
  });

  test('enforces a three-minute gap', () {
    final now = DateTime(2026, 9, 16, 12);
    expect(
      shouldShowInterstitial(
        optedOut: false,
        sdkReady: true,
        adReady: true,
        fullScreenExits: 4,
        lastShownAt: now.subtract(const Duration(minutes: 2)),
        now: now,
      ),
      isFalse,
    );
    expect(
      shouldShowInterstitial(
        optedOut: false,
        sdkReady: true,
        adReady: true,
        fullScreenExits: 4,
        lastShownAt: now.subtract(const Duration(minutes: 3)),
        now: now,
      ),
      isTrue,
    );
  });

  test('does not ad when returning from scan result to camera', () {
    expect(
      shouldSkipAdForPop(
        poppedName: '/scan/result',
        previousName: '/scan',
      ),
      isTrue,
    );
    expect(
      shouldSkipAdForPop(poppedName: 'scan', previousName: '/'),
      isFalse,
    );
    expect(
      shouldSkipAdForPop(poppedName: 'create', previousName: '/'),
      isFalse,
    );
    expect(
      shouldSkipAdForPop(poppedName: 'settings', previousName: '/'),
      isTrue,
    );
  });

  test('only the Remove Ads product unlocks ads', () {
    expect(
      unlocksRemoveAds(
        productId: 'dev.gamelogic.qrvault.remove_ads',
        incomingProductId: 'dev.gamelogic.qrvault.remove_ads',
        isPurchasedOrRestored: true,
      ),
      isTrue,
    );
    expect(
      unlocksRemoveAds(
        productId: 'dev.gamelogic.qrvault.remove_ads',
        incomingProductId: 'dev.gamelogic.qrvault.remove_ads',
        isPurchasedOrRestored: false,
      ),
      isFalse,
    );
    expect(
      unlocksRemoveAds(
        productId: 'dev.gamelogic.qrvault.remove_ads',
        incomingProductId: 'other.sku',
        isPurchasedOrRestored: true,
      ),
      isFalse,
    );
  });
}
