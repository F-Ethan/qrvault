import 'app_secrets.dart';

class AppConstants {
  AppConstants._();

  // Supabase — values live in app_secrets.dart (gitignored)
  static const String supabaseUrl = AppSecrets.supabaseUrl;
  static const String supabaseAnonKey = AppSecrets.supabaseAnonKey;

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
}
