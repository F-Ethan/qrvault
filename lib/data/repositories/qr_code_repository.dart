import 'dart:math' as math;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/qr_code_model.dart';

// Haversine formula — distance in km between two lat/lng points. Shared by
// the repository (radius filtering) and the UI (nearby-first sorting).
double haversineKm(double lat1, double lon1, double lat2, double lon2) {
  const r = 6371.0; // Earth radius in km
  final dLat = _toRad(lat2 - lat1);
  final dLon = _toRad(lon2 - lon1);
  final sinDLat = math.sin(dLat / 2);
  final sinDLon = math.sin(dLon / 2);
  final a = sinDLat * sinDLat +
      math.cos(_toRad(lat1)) * math.cos(_toRad(lat2)) * sinDLon * sinDLon;
  return r * 2 * math.asin(math.sqrt(a));
}

double _toRad(double deg) => deg * math.pi / 180;

// -- Abstract interface --
// Every method goes through this contract. If we ever add a local
// cache or swap backends, we just write a new class implementing this.
// Default public visibility by type — url/email are public, others private.
bool defaultIsPublic(QrCodeType type) =>
    type == QrCodeType.url || type == QrCodeType.email;

// Types that contain potentially sensitive data and warrant a warning
// when the user tries to make them public.
const sensitiveTypes = {
  QrCodeType.wifi,
  QrCodeType.contact,
  QrCodeType.text,
};

bool isSensitiveType(QrCodeType type) => sensitiveTypes.contains(type);

String sensitiveWarning(QrCodeType type) => switch (type) {
      QrCodeType.wifi =>
        'This QR code contains your WiFi password. Making it public will allow anyone nearby to see your network credentials.',
      QrCodeType.contact =>
        'This QR code contains personal contact information (name, phone, email). Making it public will share these details with others nearby.',
      QrCodeType.text =>
        'This QR code may contain sensitive text. Making it public will allow others nearby to see its contents.',
      _ => 'Are you sure you want to make this code visible to others nearby?',
    };

abstract class QrCodeRepository {
  Future<List<QrCodeModel>> getAll();
  Future<QrCodeModel?> getById(String id);
  Future<QrCodeModel> save(QrCodeModel qrCode);
  Future<QrCodeModel> update(QrCodeModel qrCode);
  Future<void> delete(String id);
  Future<List<QrCodeModel>> filterByType(QrCodeType type);
  Future<List<QrCodeModel>> filterByPlace(String placeName);
  Future<List<QrCodeModel>> getNearby(double lat, double lng, double radiusKm);
  Future<List<QrCodeModel>> getPublicNearby(
      double lat, double lng, double radiusKm);
  Future<List<QrCodeModel>> getAllPublic();
}

// -- Supabase implementation --
class SupabaseQrCodeRepository implements QrCodeRepository {
  final SupabaseClient _client;
  static const _table = 'qr_codes';

  SupabaseQrCodeRepository(this._client);

  @override
  Future<List<QrCodeModel>> getAll() async {
    final response = await _client
        .from(_table)
        .select()
        .order('created_at', ascending: false);
    return (response as List).map((e) => QrCodeModel.fromJson(e)).toList();
  }

  @override
  Future<QrCodeModel?> getById(String id) async {
    final response = await _client
        .from(_table)
        .select()
        .eq('id', id)
        .maybeSingle();
    if (response == null) return null;
    return QrCodeModel.fromJson(response);
  }

  @override
  Future<QrCodeModel> save(QrCodeModel qrCode) async {
    // Remove id and updated_at — Supabase generates these on insert
    final payload = qrCode.toJson()
      ..remove('id')
      ..remove('updated_at');
    final response = await _client
        .from(_table)
        .insert(payload)
        .select()
        .single();
    return QrCodeModel.fromJson(response);
  }

  @override
  Future<QrCodeModel> update(QrCodeModel qrCode) async {
    // Remove created_at — it should never change
    final payload = qrCode.toJson()..remove('created_at');
    final response = await _client
        .from(_table)
        .update(payload)
        .eq('id', qrCode.id)
        .select()
        .single();
    return QrCodeModel.fromJson(response);
  }

  @override
  Future<void> delete(String id) async {
    await _client.from(_table).delete().eq('id', id);
  }

  @override
  Future<List<QrCodeModel>> filterByType(QrCodeType type) async {
    final response = await _client
        .from(_table)
        .select()
        .eq('type', type.name)
        .order('created_at', ascending: false);
    return (response as List).map((e) => QrCodeModel.fromJson(e)).toList();
  }

  @override
  Future<List<QrCodeModel>> filterByPlace(String placeName) async {
    final response = await _client
        .from(_table)
        .select()
        .or('first_scanned_place.ilike.%$placeName%,'
            'last_scanned_place.ilike.%$placeName%')
        .order('created_at', ascending: false);
    return (response as List).map((e) => QrCodeModel.fromJson(e)).toList();
  }

  @override
  Future<List<QrCodeModel>> getNearby(
      double lat, double lng, double radiusKm) async {
    // Pull all codes that have location data and filter in Dart.
    // For a family-scale app this is perfectly fast; at larger scale
    // we'd add a PostGIS extension and do this in SQL.
    final all = await getAll();
    return all.where((qr) {
      final qrLat = qr.lastScannedLat ?? qr.firstScannedLat;
      final qrLng = qr.lastScannedLng ?? qr.firstScannedLng;
      if (qrLat == null || qrLng == null) return false;
      return haversineKm(lat, lng, qrLat, qrLng) <= radiusKm;
    }).toList();
  }

  @override
  Future<List<QrCodeModel>> getPublicNearby(
      double lat, double lng, double radiusKm) async {
    // Fetch all public codes that have location data attached.
    // RLS must allow SELECT where is_public = true (see migration SQL).
    final response = await _client
        .from(_table)
        .select()
        .eq('is_public', true)
        .not('last_scanned_lat', 'is', null);
    final all =
        (response as List).map((e) => QrCodeModel.fromJson(e)).toList();
    return all.where((qr) {
      final qrLat = qr.lastScannedLat ?? qr.firstScannedLat;
      final qrLng = qr.lastScannedLng ?? qr.firstScannedLng;
      if (qrLat == null || qrLng == null) return false;
      return haversineKm(lat, lng, qrLat, qrLng) <= radiusKm;
    }).toList();
  }

  @override
  Future<List<QrCodeModel>> getAllPublic() async {
    // Unrestricted by location — used for text search across all public
    // codes, and for browsing when the user turns off "Local only".
    final response = await _client
        .from(_table)
        .select()
        .eq('is_public', true)
        .order('scan_count', ascending: false);
    return (response as List).map((e) => QrCodeModel.fromJson(e)).toList();
  }
}
