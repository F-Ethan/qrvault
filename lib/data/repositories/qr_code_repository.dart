import 'dart:math' as math;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/qr_code_model.dart';
import '../qr_payload.dart';

double haversineKm(double lat1, double lon1, double lat2, double lon2) {
  const r = 6371.0;
  final dLat = _toRad(lat2 - lat1);
  final dLon = _toRad(lon2 - lon1);
  final sinDLat = math.sin(dLat / 2);
  final sinDLon = math.sin(dLon / 2);
  final a = sinDLat * sinDLat +
      math.cos(_toRad(lat1)) * math.cos(_toRad(lat2)) * sinDLon * sinDLon;
  return r * 2 * math.asin(math.sqrt(a));
}

double _toRad(double deg) => deg * math.pi / 180;

bool defaultIsPublic(QrCodeType type) =>
    type == QrCodeType.url || type == QrCodeType.email;

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

class ScanRecordResult {
  final QrCodeModel? code;
  final bool isOwn;

  const ScanRecordResult({this.code, this.isOwn = false});
}

abstract class QrCodeRepository {
  Future<List<QrCodeModel>> getAll();
  Future<QrCodeModel?> getById(String id);
  Future<QrCodeModel> save(QrCodeModel qrCode);
  Future<QrCodeModel> update(QrCodeModel qrCode);
  Future<void> delete(String id);
  Future<void> removeMembership(String qrCodeId);
  Future<QrCodeModel> upsertMembership({
    required String qrCodeId,
    bool? isPinned,
    String? customLabel,
    bool incrementScan = false,
  });
  Future<ScanRecordResult> recordScan({
    required String content,
    double? lat,
    double? lng,
    String? place,
    bool saveMembership = false,
  });
  Future<QrCodeModel?> findExisting(String content);
  Future<List<QrCodeModel>> filterByType(QrCodeType type);
  Future<List<QrCodeModel>> filterByPlace(String placeName);
  Future<List<QrCodeModel>> getNearby(double lat, double lng, double radiusKm);
  Future<List<QrCodeModel>> getPublicNearby(
      double lat, double lng, double radiusKm);
  Future<List<QrCodeModel>> getAllPublic();
  Future<List<QrCodeNote>> listNotes(String qrCodeId);
  Future<QrCodeNote> addNote(String qrCodeId, String body);
  Future<void> deleteNote(String noteId);
}

class SupabaseQrCodeRepository implements QrCodeRepository {
  final SupabaseClient _client;
  static const _table = 'qr_codes';
  static const _memberships = 'qr_code_memberships';
  static const _notes = 'qr_code_notes';

  SupabaseQrCodeRepository(this._client);

  String? get _uid => _client.auth.currentUser?.id;

  List<QrCodeModel> _parseMembershipList(dynamic response) {
    return (response as List)
        .map((e) => QrCodeModel.fromJson(Map<String, dynamic>.from(e as Map)))
        .where((c) => c.id.isNotEmpty)
        .toList();
  }

  Future<QrCodeModel> _mergeMembership(QrCodeModel code) async {
    final uid = _uid;
    if (uid == null) return code;
    final mem = await _client
        .from(_memberships)
        .select()
        .eq('user_id', uid)
        .eq('qr_code_id', code.id)
        .maybeSingle();
    if (mem == null) return code;
    return QrCodeModel.fromJson({
      ...code.toJson(),
      'membership': mem,
    });
  }

  @override
  Future<List<QrCodeModel>> getAll() async {
    final uid = _uid;
    if (uid == null) return [];
    final response = await _client
        .from(_memberships)
        .select('custom_label, is_pinned, my_scan_count, qr_code_id, qr_codes(*)')
        .eq('user_id', uid)
        .order('updated_at', ascending: false);
    return _parseMembershipList(response);
  }

  @override
  Future<QrCodeModel?> getById(String id) async {
    final response = await _client
        .from(_table)
        .select()
        .eq('id', id)
        .maybeSingle();
    if (response == null) return null;
    return _mergeMembership(QrCodeModel.fromJson(response));
  }

  @override
  Future<QrCodeModel> save(QrCodeModel qrCode) async {
    final uid = _uid;
    if (uid == null) {
      throw StateError('Not signed in');
    }
    final payload = qrCode.toJson()
      ..remove('id')
      ..remove('updated_at')
      ..['user_id'] = uid;
    final response = await _client
        .from(_table)
        .insert(payload)
        .select()
        .single();
    final saved = QrCodeModel.fromJson(response);
    await _client.from(_memberships).upsert({
      'user_id': uid,
      'qr_code_id': saved.id,
      'is_pinned': qrCode.isPinned,
      'my_scan_count': qrCode.myScanCount > 0 ? qrCode.myScanCount : 1,
      'last_scanned_at': DateTime.now().toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
    });
    return _mergeMembership(saved);
  }

  @override
  Future<QrCodeModel> update(QrCodeModel qrCode) async {
    final uid = _uid;
    if (uid == null) {
      throw StateError('Not signed in');
    }
    final payload = qrCode.toJson()
      ..remove('created_at')
      ..['user_id'] = uid;
    final response = await _client
        .from(_table)
        .update(payload)
        .eq('id', qrCode.id)
        .eq('user_id', uid)
        .select()
        .single();
    return _mergeMembership(QrCodeModel.fromJson(response));
  }

  @override
  Future<void> delete(String id) async {
    final uid = _uid;
    if (uid == null) {
      throw StateError('Not signed in');
    }
    await _client.from(_table).delete().eq('id', id).eq('user_id', uid);
  }

  @override
  Future<void> removeMembership(String qrCodeId) async {
    final uid = _uid;
    if (uid == null) {
      throw StateError('Not signed in');
    }
    await _client
        .from(_memberships)
        .delete()
        .eq('user_id', uid)
        .eq('qr_code_id', qrCodeId);
  }

  @override
  Future<QrCodeModel> upsertMembership({
    required String qrCodeId,
    bool? isPinned,
    String? customLabel,
    bool incrementScan = false,
  }) async {
    final uid = _uid;
    if (uid == null) {
      throw StateError('Not signed in');
    }
    final existing = await _client
        .from(_memberships)
        .select()
        .eq('user_id', uid)
        .eq('qr_code_id', qrCodeId)
        .maybeSingle();
    final nextCount = incrementScan
        ? ((existing?['my_scan_count'] as int?) ?? 0) + 1
        : (existing?['my_scan_count'] as int? ?? 0);
    await _client.from(_memberships).upsert({
      'user_id': uid,
      'qr_code_id': qrCodeId,
      'is_pinned': isPinned ?? existing?['is_pinned'] ?? false,
      'custom_label': customLabel ?? existing?['custom_label'],
      'my_scan_count': nextCount,
      'last_scanned_at': DateTime.now().toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
    });
    final code = await getById(qrCodeId);
    if (code == null) {
      throw StateError('Code not found');
    }
    return code;
  }

  @override
  Future<ScanRecordResult> recordScan({
    required String content,
    double? lat,
    double? lng,
    String? place,
    bool saveMembership = false,
  }) async {
    final response = await _client.rpc('record_qr_scan', params: {
      'p_content': content,
      'p_lat': lat,
      'p_lng': lng,
      'p_place': place,
      'p_save_membership': saveMembership,
    });
    if (response == null) return const ScanRecordResult();
    final map = Map<String, dynamic>.from(response as Map);
    final codeJson = map['code'];
    if (codeJson == null) return const ScanRecordResult();
    return ScanRecordResult(
      code: QrCodeModel.fromScanRpc(map),
      isOwn: map['is_own'] as bool? ?? false,
    );
  }

  @override
  Future<QrCodeModel?> findExisting(String content) async {
    final uid = _uid;
    if (uid != null) {
      final own = await _client
          .from(_table)
          .select()
          .eq('user_id', uid)
          .eq('content', content)
          .maybeSingle();
      if (own != null) {
        return _mergeMembership(QrCodeModel.fromJson(own));
      }
    }
    final publicRows = await _client
        .from(_table)
        .select()
        .eq('is_public', true)
        .eq('content', content)
        .order('public_scan_count', ascending: false)
        .limit(1);
    final list = publicRows as List;
    if (list.isNotEmpty) {
      return _mergeMembership(
        QrCodeModel.fromJson(Map<String, dynamic>.from(list.first as Map)),
      );
    }
    return _findByTemplate(content, uid);
  }

  Future<QrCodeModel?> _findByTemplate(String content, String? uid) async {
    final template = QrPayloadBlueprint.parse(content).dateTemplate();
    if (template == content.trim()) return null;
    if (uid != null) {
      final own = await _client
          .from(_table)
          .select()
          .eq('user_id', uid)
          .eq('payload_template', template)
          .maybeSingle();
      if (own != null) {
        return _mergeMembership(QrCodeModel.fromJson(own));
      }
    }
    final publicRows = await _client
        .from(_table)
        .select()
        .eq('is_public', true)
        .eq('payload_template', template)
        .order('public_scan_count', ascending: false)
        .limit(1);
    final list = publicRows as List;
    if (list.isEmpty) return null;
    return _mergeMembership(
      QrCodeModel.fromJson(Map<String, dynamic>.from(list.first as Map)),
    );
  }

  @override
  Future<List<QrCodeModel>> filterByType(QrCodeType type) async {
    final all = await getAll();
    return all.where((c) => c.type == type).toList();
  }

  @override
  Future<List<QrCodeModel>> filterByPlace(String placeName) async {
    final q = placeName.toLowerCase();
    final all = await getAll();
    return all.where((c) {
      return (c.firstScannedPlace ?? '').toLowerCase().contains(q) ||
          (c.lastScannedPlace ?? '').toLowerCase().contains(q);
    }).toList();
  }

  @override
  Future<List<QrCodeModel>> getNearby(
      double lat, double lng, double radiusKm) async {
    final all = await getAll();
    return all.where((qr) {
      final qrLat = qr.mapLat;
      final qrLng = qr.mapLng;
      if (qrLat == null || qrLng == null) return false;
      return haversineKm(lat, lng, qrLat, qrLng) <= radiusKm;
    }).toList();
  }

  @override
  Future<List<QrCodeModel>> getPublicNearby(
      double lat, double lng, double radiusKm) async {
    final response = await _client.from(_table).select().eq('is_public', true);
    final all =
        (response as List).map((e) => QrCodeModel.fromJson(e)).toList();
    return all.where((qr) {
      final qrLat = qr.mapLat;
      final qrLng = qr.mapLng;
      if (qrLat == null || qrLng == null) return false;
      return haversineKm(lat, lng, qrLat, qrLng) <= radiusKm;
    }).toList();
  }

  @override
  Future<List<QrCodeModel>> getAllPublic() async {
    final response = await _client
        .from(_table)
        .select()
        .eq('is_public', true)
        .order('public_scan_count', ascending: false);
    return (response as List).map((e) => QrCodeModel.fromJson(e)).toList();
  }

  @override
  Future<List<QrCodeNote>> listNotes(String qrCodeId) async {
    final response = await _client
        .from(_notes)
        .select()
        .eq('qr_code_id', qrCodeId)
        .order('created_at', ascending: false);
    return (response as List)
        .map((e) => QrCodeNote.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  @override
  Future<QrCodeNote> addNote(String qrCodeId, String body) async {
    final uid = _uid;
    if (uid == null) {
      throw StateError('Not signed in');
    }
    final response = await _client
        .from(_notes)
        .insert({
          'qr_code_id': qrCodeId,
          'user_id': uid,
          'body': body.trim(),
        })
        .select()
        .single();
    return QrCodeNote.fromJson(response);
  }

  @override
  Future<void> deleteNote(String noteId) async {
    final uid = _uid;
    if (uid == null) {
      throw StateError('Not signed in');
    }
    await _client.from(_notes).delete().eq('id', noteId).eq('user_id', uid);
  }
}
