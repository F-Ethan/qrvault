import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/ads/ads_service.dart';
import '../core/ads/remove_ads_iap.dart';

const kRemoveAdsPurchasedPrefKey = 'remove_ads_purchased';

var _initialRemoveAdsPurchased = false;

void setInitialRemoveAdsPurchased(bool value) {
  _initialRemoveAdsPurchased = value;
}

class RemoveAdsState {
  const RemoveAdsState({
    this.purchased = false,
    this.priceLabel,
    this.busy = false,
    this.message,
  });

  final bool purchased;
  final String? priceLabel;
  final bool busy;
  final String? message;

  RemoveAdsState copyWith({
    bool? purchased,
    String? priceLabel,
    bool? busy,
    String? message,
    bool clearMessage = false,
  }) {
    return RemoveAdsState(
      purchased: purchased ?? this.purchased,
      priceLabel: priceLabel ?? this.priceLabel,
      busy: busy ?? this.busy,
      message: clearMessage ? null : (message ?? this.message),
    );
  }
}

final removeAdsProvider =
    NotifierProvider<RemoveAdsNotifier, RemoveAdsState>(RemoveAdsNotifier.new);

class RemoveAdsNotifier extends Notifier<RemoveAdsState> {
  late final RemoveAdsIap _iap;

  @override
  RemoveAdsState build() {
    _iap = RemoveAdsIap(
      onUnlocked: _unlock,
      onPrice: (price) {
        state = state.copyWith(priceLabel: price);
      },
      onError: (message) {
        state = state.copyWith(busy: false, message: message);
      },
      onIdle: () {
        if (!state.purchased) state = state.copyWith(busy: false);
      },
    );
    ref.onDispose(_iap.dispose);
    Future.microtask(_iap.start);
    return RemoveAdsState(purchased: _initialRemoveAdsPurchased);
  }

  Future<void> buy() async {
    if (state.purchased || state.busy) return;
    state = state.copyWith(busy: true, clearMessage: true);
    try {
      await _iap.buy();
    } catch (e) {
      state = state.copyWith(busy: false, message: '$e');
    }
  }

  Future<void> restore() async {
    if (state.purchased || state.busy) return;
    state = state.copyWith(busy: true, clearMessage: true);
    try {
      await _iap.restore();
      await Future<void>.delayed(const Duration(milliseconds: 800));
      if (!state.purchased) {
        state = state.copyWith(
          busy: false,
          message: 'No purchase found for this Apple ID.',
        );
      }
    } catch (e) {
      state = state.copyWith(busy: false, message: '$e');
    }
  }

  Future<void> _unlock() async {
    state = state.copyWith(purchased: true, busy: false, clearMessage: true);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(kRemoveAdsPurchasedPrefKey, true);
    ref.read(adsServiceProvider).clear();
  }
}

final adsServiceProvider = Provider<AdsService>((ref) {
  final service = AdsService(
    optedOut: () => ref.read(removeAdsProvider).purchased,
  );
  ref.onDispose(service.dispose);
  Future.microtask(service.start);
  return service;
});
