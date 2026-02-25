import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/qr_code_model.dart';

// -- Abstract interface --
// Every method goes through this contract. If we ever add a local
// cache or swap backends, we just write a new class implementing this.
abstract class QrCodeRepository {
  Future<List<QrCodeModel>> getAll();
  Future<QrCodeModel?> getById(String id);
  Future<QrCodeModel> save(QrCodeModel qrCode);
  Future<QrCodeModel> update(QrCodeModel qrCode);
  Future<void> delete(String id);
  Future<List<QrCodeModel>> filterByType(QrCodeType type);
  Future<List<QrCodeModel>> filterByPlace(String placeName);
  Future<List<QrCodeModel>> getNearby(double lat, double lng, double radiusKm);
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
      return _haversineKm(lat, lng, qrLat, qrLng) <= radiusKm;
    }).toList();
  }

  // Haversine formula — calculates distance in km between two lat/lng points
  double _haversineKm(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371.0; // Earth radius in km
    final dLat = _toRad(lat2 - lat1);
    final dLon = _toRad(lon2 - lon1);
    final a = _sin2(dLat / 2) +
        _cos(_toRad(lat1)) * _cos(_toRad(lat2)) * _sin2(dLon / 2);
    return r * 2 * _asin(_sqrt(a));
  }

  double _toRad(double deg) => deg * 3.141592653589793 / 180;
  double _sin2(double x) => _sin(x) * _sin(x);
  double _sin(double x) => x - x * x * x / 6 + x * x * x * x * x / 120;
  double _cos(double x) => 1 - x * x / 2 + x * x * x * x / 24;
  double _asin(double x) => x + x * x * x / 6;
  double _sqrt(double x) {
    if (x <= 0) return 0;
    double r = x;
    for (int i = 0; i < 20; i++) {
      r = (r + x / r) / 2;
    }
    return r;
  }
}
