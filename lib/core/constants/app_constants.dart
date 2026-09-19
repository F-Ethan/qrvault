import 'app_secrets.dart';

class AppConstants {
  AppConstants._();

  // Supabase — values live in app_secrets.dart (gitignored)
  static const String supabaseUrl = AppSecrets.supabaseUrl;
  static const String supabaseAnonKey = AppSecrets.supabaseAnonKey;

  static const String mapboxAccessToken = String.fromEnvironment(
    'MAPBOX_ACCESS_TOKEN',
    defaultValue: AppSecrets.mapboxAccessToken,
  );

  // Deep link used for email confirmation / password reset callbacks.
  // Must also be added to Supabase → Authentication → URL Configuration →
  // Redirect URLs, and registered as a URL scheme on iOS/Android.
  static const String authRedirectUrl = 'qrvault://auth-callback';

  // Location — how close you need to be for a code to show in "Near You"
  // 8 km ≈ 5 miles
  static const double nearbyRadiusKm = 8.0;

  // QR Code defaults
  static const String defaultForegroundColor = '#000000';
  static const String defaultBackgroundColor = '#FFFFFF';

  // iOS AdMob (App Store 6759879006).
  static const String admobIosAppId =
      'ca-app-pub-7671007992790429~9351448191';
  static const String admobInterstitialUnitId =
      'ca-app-pub-7671007992790429/4384784287';

  /// Non-consumable StoreKit product. Create the same ID in App Store Connect.
  static const String removeAdsProductId = 'dev.gamelogic.qrvault.remove_ads';
}
