class AppConstants {
  AppConstants._();

  // Supabase — injected at build time via --dart-define-from-file=dart_defines/dev.json
  // Never hardcode these values here; see dart_defines/dev.json.template
  static const String supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const String supabaseAnonKey =
      String.fromEnvironment('SUPABASE_ANON_KEY');

  // Location — how close you need to be for a code to show in "Near You"
  static const double nearbyRadiusKm = 0.5;

  // QR Code defaults
  static const String defaultForegroundColor = '#000000';
  static const String defaultBackgroundColor = '#FFFFFF';
}
