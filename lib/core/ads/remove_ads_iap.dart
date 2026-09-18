import 'dart:async';

import 'package:in_app_purchase/in_app_purchase.dart';

import '../constants/app_constants.dart';
import 'ads_gate.dart';

class RemoveAdsIap {
  RemoveAdsIap({
    required this.onUnlocked,
    required this.onPrice,
    required this.onError,
    required this.onIdle,
    InAppPurchase? store,
  }) : _store = store ?? InAppPurchase.instance;

  final void Function() onUnlocked;
  final void Function(String price) onPrice;
  final void Function(String message) onError;
  final void Function() onIdle;

  final InAppPurchase _store;
  StreamSubscription<List<PurchaseDetails>>? _sub;
  ProductDetails? _product;

  Future<void> start() async {
    _sub ??= _store.purchaseStream.listen(
      _onPurchases,
      onError: (Object e) => onError('$e'),
    );
    if (!await _store.isAvailable()) return;
    final response = await _store.queryProductDetails({
      AppConstants.removeAdsProductId,
    });
    if (response.productDetails.isEmpty) return;
    _product = response.productDetails.first;
    onPrice(_product!.price);
  }

  Future<void> buy() async {
    final product = _product;
    if (product == null) {
      onError(
        'Remove Ads is not in the store yet. Try Restore Purchase if you already bought it.',
      );
      return;
    }
    await _store.buyNonConsumable(
      purchaseParam: PurchaseParam(productDetails: product),
    );
  }

  Future<void> restore() => _store.restorePurchases();

  Future<void> _onPurchases(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      final unlocked = unlocksRemoveAds(
        productId: AppConstants.removeAdsProductId,
        incomingProductId: purchase.productID,
        isPurchasedOrRestored: purchase.status == PurchaseStatus.purchased ||
            purchase.status == PurchaseStatus.restored,
      );
      if (unlocked) onUnlocked();
      if (purchase.status == PurchaseStatus.error) {
        onError(purchase.error?.message ?? 'Purchase failed.');
      }
      if (purchase.status == PurchaseStatus.canceled) onIdle();
      if (purchase.pendingCompletePurchase) {
        await _store.completePurchase(purchase);
      }
    }
  }

  void dispose() {
    _sub?.cancel();
    _sub = null;
  }
}
