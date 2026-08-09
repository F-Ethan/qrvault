import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../data/models/qr_code_model.dart';
import '../data/repositories/qr_code_repository.dart';

// -- Auth --
// Exposes a stream of auth changes so every screen can react to
// sign-in / sign-out without any extra plumbing.
final authStateProvider = StreamProvider<AuthState>((ref) {
  return Supabase.instance.client.auth.onAuthStateChange;
});

// -- Repository --
// A single shared instance of the Supabase repository.
final qrCodeRepositoryProvider = Provider<QrCodeRepository>((ref) {
  return SupabaseQrCodeRepository(Supabase.instance.client);
});

// -- QR Code list --
// AsyncNotifier handles loading / error / data states automatically.
final qrCodesProvider =
    AsyncNotifierProvider<QrCodesNotifier, List<QrCodeModel>>(
  QrCodesNotifier.new,
);

// -- Nearby public codes --
// Keyed by (lat, lng, radiusKm) — fetched once after location is resolved.
final nearbyPublicProvider = FutureProvider.autoDispose
    .family<List<QrCodeModel>, ({double lat, double lng, double radiusKm})>(
  (ref, params) => ref
      .read(qrCodeRepositoryProvider)
      .getPublicNearby(params.lat, params.lng, params.radiusKm),
);

// -- All public codes, unrestricted by location — powers search across all
// public codes and "All Public" browsing when "Local only" is off.
final allPublicProvider =
    FutureProvider.autoDispose<List<QrCodeModel>>((ref) {
  return ref.read(qrCodeRepositoryProvider).getAllPublic();
});

// -- Single code by ID — checks user's list first, then fetches from DB.
// Allows viewing other users' public codes from Near You / Popular.
final codeByIdProvider =
    FutureProvider.autoDispose.family<QrCodeModel?, String>((ref, id) async {
  final userCodes = ref.watch(qrCodesProvider).asData?.value ?? [];
  final local = userCodes.where((c) => c.id == id).firstOrNull;
  if (local != null) return local;
  return ref.read(qrCodeRepositoryProvider).getById(id);
});

class QrCodesNotifier extends AsyncNotifier<List<QrCodeModel>> {
  @override
  Future<List<QrCodeModel>> build() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return [];
    return ref.read(qrCodeRepositoryProvider).getAll();
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(qrCodeRepositoryProvider).getAll(),
    );
  }

  Future<void> add(QrCodeModel qrCode) async {
    final repo = ref.read(qrCodeRepositoryProvider);
    final saved = await repo.save(qrCode);
    // Prepend the new code so it appears first in the list immediately
    state = state.whenData((codes) => [saved, ...codes]);
  }

  Future<void> updateCode(QrCodeModel qrCode) async {
    final repo = ref.read(qrCodeRepositoryProvider);
    final updated = await repo.update(qrCode);
    state = state.whenData(
      (codes) => codes.map((c) => c.id == updated.id ? updated : c).toList(),
    );
  }

  Future<void> remove(String id) async {
    final repo = ref.read(qrCodeRepositoryProvider);
    await repo.delete(id);
    state = state.whenData((codes) => codes.where((c) => c.id != id).toList());
  }
}
