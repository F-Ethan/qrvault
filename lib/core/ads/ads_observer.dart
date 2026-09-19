import 'package:flutter/material.dart';

import 'ads_service.dart';

class AdsRouteObserver extends NavigatorObserver {
  AdsRouteObserver(this._ads);

  final AdsService _ads;

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _ads.maybeShowAfterFullScreen(
      poppedName: route.settings.name,
      previousName: previousRoute?.settings.name,
    );
  }
}
