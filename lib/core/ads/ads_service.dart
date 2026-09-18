import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../constants/app_constants.dart';
import 'ads_gate.dart';

class AdsService {
  AdsService({required this.optedOut});

  final bool Function() optedOut;

  InterstitialAd? _ad;
  var _sdkReady = false;
  var _loading = false;
  var _fullScreenExits = 0;
  DateTime? _lastShownAt;

  bool get _supported =>
      !kIsWeb && (Platform.isIOS || Platform.isAndroid);

  Future<void> start() async {
    if (!_supported || optedOut()) return;
    try {
      if (_sdkReady) {
        await _load();
        return;
      }
      await _gatherConsentThenInit();
    } catch (_) {}
  }

  Future<void> _gatherConsentThenInit() async {
    final consentDone = Completer<void>();
    ConsentInformation.instance.requestConsentInfoUpdate(
      ConsentRequestParameters(),
      () async {
        await ConsentForm.loadAndShowConsentFormIfRequired((_) {});
        if (!consentDone.isCompleted) consentDone.complete();
      },
      (_) {
        if (!consentDone.isCompleted) consentDone.complete();
      },
    );
    await consentDone.future;
    if (optedOut()) return;
    if (!await ConsentInformation.instance.canRequestAds()) return;
    await MobileAds.instance.initialize();
    _sdkReady = true;
    await _load();
  }

  Future<void> _load() async {
    if (!_supported || optedOut() || !_sdkReady || _loading || _ad != null) {
      return;
    }
    _loading = true;
    await InterstitialAd.load(
      adUnitId: AppConstants.admobInterstitialUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _ad = ad;
          _loading = false;
          ad.fullScreenContentCallback = FullScreenContentCallback(
            onAdDismissedFullScreenContent: (ad) {
              ad.dispose();
              _ad = null;
              _load();
            },
            onAdFailedToShowFullScreenContent: (ad, _) {
              ad.dispose();
              _ad = null;
              _load();
            },
          );
        },
        onAdFailedToLoad: (_) {
          _loading = false;
          _ad = null;
        },
      ),
    );
  }

  Future<void> maybeShowAfterFullScreen({
    String? poppedName,
    String? previousName,
  }) async {
    if (shouldSkipAdForPop(
      poppedName: poppedName,
      previousName: previousName,
    )) {
      return;
    }
    _fullScreenExits += 1;
    if (!shouldShowInterstitial(
      optedOut: optedOut(),
      sdkReady: _sdkReady,
      adReady: _ad != null,
      fullScreenExits: _fullScreenExits,
      lastShownAt: _lastShownAt,
      now: DateTime.now(),
    )) {
      return;
    }
    final ad = _ad;
    if (ad == null) return;
    _ad = null;
    _lastShownAt = DateTime.now();
    await ad.show();
  }

  void clear() {
    _ad?.dispose();
    _ad = null;
    _sdkReady = false;
  }

  void dispose() => clear();
}
