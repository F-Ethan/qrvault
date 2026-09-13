import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../data/models/qr_code_model.dart';
import '../data/repositories/qr_code_repository.dart';

final authStateProvider = StreamProvider<AuthState>((ref) {
  return Supabase.instance.client.auth.onAuthStateChange;
});

final qrCodeRepositoryProvider = Provider<QrCodeRepository>((ref) {
  return SupabaseQrCodeRepository(Supabase.instance.client);
});

final qrCodesProvider =
    AsyncNotifierProvider<QrCodesNotifier, List<QrCodeModel>>(
  QrCodesNotifier.new,
);

final nearbyPublicProvider = FutureProvider.autoDispose
    .family<List<QrCodeModel>, ({double lat, double lng, double radiusKm})>(
  (ref, params) => ref
      .read(qrCodeRepositoryProvider)
      .getPublicNearby(params.lat, params.lng, params.radiusKm),
);

final allPublicProvider =
    FutureProvider.autoDispose<List<QrCodeModel>>((ref) {
  return ref.read(qrCodeRepositoryProvider).getAllPublic();
});

final codeByIdProvider =
    FutureProvider.autoDispose.family<QrCodeModel?, String>((ref, id) async {
  final userCodes = ref.watch(qrCodesProvider).asData?.value ?? [];
  final local = userCodes.where((c) => c.id == id).firstOrNull;
  if (local != null) return local;
  return ref.read(qrCodeRepositoryProvider).getById(id);
});

final notesProvider =
    FutureProvider.autoDispose.family<List<QrCodeNote>, String>((ref, id) {
  return ref.read(qrCodeRepositoryProvider).listNotes(id);
});

class QrCodesNotifier extends AsyncNotifier<List<QrCodeModel>> {
  @override
  Future<List<QrCodeModel>> build() async {
    ref.watch(authStateProvider);
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return [];
    return ref.read(qrCodeRepositoryProvider).getAll();
  }

  Future<void> refresh() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      state = const AsyncData([]);
      return;
    }
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(qrCodeRepositoryProvider).getAll(),
    );
  }

  void _upsertLocal(QrCodeModel updated) {
    state = state.whenData((codes) {
      final exists = codes.any((c) => c.id == updated.id);
      if (!exists) return [updated, ...codes];
      return codes.map((c) => c.id == updated.id ? updated : c).toList();
    });
  }

  Future<void> add(QrCodeModel qrCode) async {
    final saved = await ref.read(qrCodeRepositoryProvider).save(qrCode);
    _upsertLocal(saved);
  }

  Future<void> updateCode(QrCodeModel qrCode) async {
    final repo = ref.read(qrCodeRepositoryProvider);
    final user = Supabase.instance.client.auth.currentUser;
    final isOwner = user != null && qrCode.userId == user.id;
    late QrCodeModel updated;
    if (isOwner) {
      updated = await repo.update(qrCode);
    } else {
      updated = await repo.upsertMembership(
        qrCodeId: qrCode.id,
        isPinned: qrCode.isPinned,
        customLabel: qrCode.customLabel,
      );
    }
    _upsertLocal(updated);
  }

  Future<QrCodeModel> togglePin(QrCodeModel code) async {
    final updated = await ref.read(qrCodeRepositoryProvider).upsertMembership(
          qrCodeId: code.id,
          isPinned: !code.isPinned,
          customLabel: code.customLabel,
        );
    _upsertLocal(updated);
    return updated;
  }

  Future<QrCodeModel> saveNickname(QrCodeModel code, String nickname) async {
    final updated = await ref.read(qrCodeRepositoryProvider).upsertMembership(
          qrCodeId: code.id,
          isPinned: code.isPinned,
          customLabel: nickname.trim().isEmpty ? null : nickname.trim(),
        );
    _upsertLocal(updated);
    return updated;
  }

  Future<ScanRecordResult> recordScan({
    required String content,
    double? lat,
    double? lng,
    String? place,
    bool saveMembership = false,
  }) async {
    final result = await ref.read(qrCodeRepositoryProvider).recordScan(
          content: content,
          lat: lat,
          lng: lng,
          place: place,
          saveMembership: saveMembership,
        );
    if (result.code != null && result.code!.hasMembership) {
      _upsertLocal(result.code!);
    }
    return result;
  }

  Future<void> remove(String id) async {
    await ref.read(qrCodeRepositoryProvider).delete(id);
    state = state.whenData((codes) => codes.where((c) => c.id != id).toList());
  }

  Future<void> removeFromLibrary(String id) async {
    await ref.read(qrCodeRepositoryProvider).removeMembership(id);
    state = state.whenData((codes) => codes.where((c) => c.id != id).toList());
  }
}
