import 'app_secrets.dart';

class AppConstants {
  AppConstants._();

  // Supabase — values live in app_secrets.dart (gitignored)
  static const String supabaseUrl = AppSecrets.supabaseUrl;
  static const String supabaseAnonKey = AppSecrets.supabaseAnonKey;

  // Location — how close you need to be for a code to show in "Near You"
  // 8 km ≈ 5 miles
  static const double nearbyRadiusKm = 8.0;

  // QR Code defaults
  static const String defaultForegroundColor = '#000000';
  static const String defaultBackgroundColor = '#FFFFFF';
}
