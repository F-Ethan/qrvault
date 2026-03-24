import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme/app_theme.dart';
import '../../data/models/qr_code_model.dart';
import '../../providers/qr_code_providers.dart';
import '../../providers/settings_providers.dart';

// ---------------------------------------------------------------------------
// Home Screen
// ---------------------------------------------------------------------------
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  Position? _userPosition;
  bool _locationLoading = true;
  bool _locationDenied = false;
  bool _locationError = false;

  @override
  void initState() {
    super.initState();
    _fetchPosition();
  }

  Future<void> _fetchPosition() async {
    setState(() {
      _locationLoading = true;
      _locationDenied = false;
      _locationError = false;
    });

    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (mounted) setState(() { _locationDenied = true; _locationLoading = false; });
        return;
      }

      Position? position = await Geolocator.getLastKnownPosition();
      position ??= await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 20),
        ),
      );

      if (mounted) setState(() { _userPosition = position; _locationLoading = false; });
    } catch (_) {
      if (mounted) setState(() { _userPosition = null; _locationLoading = false; _locationError = true; });
    }
  }

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  String _nameSuffix() {
    final user = Supabase.instance.client.auth.currentUser;
    final fullName = user?.userMetadata?['full_name'] as String?;
    if (fullName != null && fullName.isNotEmpty) {
      return ', ${fullName.split(' ').first}';
    }
    final prefix = (user?.email ?? '').split('@').first;
    if (prefix.isNotEmpty) return ', $prefix';
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final isGuest = ref.watch(guestModeProvider);
    final codesAsync = ref.watch(qrCodesProvider);
    final radiusKm = ref.watch(nearbyRadiusProvider) * 1.60934;
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;

    // Fetch public nearby codes from all users.
    List<QrCodeModel> publicNearby = const [];
    if (!isGuest && !_locationLoading && !_locationDenied && _userPosition != null) {
      final nearbyAsync = ref.watch(nearbyPublicProvider((
        lat: _userPosition!.latitude,
        lng: _userPosition!.longitude,
        radiusKm: radiusKm,
      )));
      publicNearby = nearbyAsync.asData?.value ?? [];
    }

    // Near You = user's own codes with nearby location + public codes from others.
    List<QrCodeModel>? nearbyCodes;
    if (!isGuest && !_locationLoading && !_locationDenied && _userPosition != null) {
      final userCodes = codesAsync.asData?.value ?? [];
      final seen = <String>{};
      final merged = <QrCodeModel>[];
      // Public codes first (includes own public + others' public).
      for (final c in publicNearby) {
        if (seen.add(c.id)) merged.add(c);
      }
      // Then user's own private codes with location nearby.
      for (final c in userCodes) {
        if (c.isPublic) continue; // already in publicNearby
        final lat = c.lastScannedLat ?? c.firstScannedLat;
        final lng = c.lastScannedLng ?? c.firstScannedLng;
        if (lat == null || lng == null) continue;
        if (seen.add(c.id)) merged.add(c);
      }
      nearbyCodes = merged;
    }

    // Popular Nearby = public codes sorted by scanCount descending.
    final popularCodes = [...publicNearby]
      ..sort((a, b) => b.scanCount.compareTo(a.scanCount));

    return Scaffold(
      appBar: AppBar(title: const Text('QRVault')),
      body: RefreshIndicator(
        onRefresh: () async {
          if (!isGuest) {
            await Future.wait([
              ref.read(qrCodesProvider.notifier).refresh(),
              _fetchPosition(),
            ]);
          }
        },
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            // ── Greeting ──────────────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                child: Text(
                  isGuest ? 'Welcome to QRVault' : '${_greeting()}${_nameSuffix()}',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
              ),
            ),

            // ── Guest sign-up prompt ───────────────────────────────────
            if (isGuest)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppTheme.primary.withValues(alpha: 0.25)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Save your QR codes', style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 6),
                        Text(
                          "You're exploring as a guest. Sign up for free to save scanned codes, create custom ones, and build your library.",
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: FilledButton(
                                onPressed: () => context.push('/sign-up'),
                                child: const Text('Sign Up Free'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () => context.push('/sign-in'),
                                child: const Text('Sign In'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),

            // ── Near You (signed-in only) ──────────────────────────────
            if (!isGuest)
              SliverToBoxAdapter(
                child: _NearbySection(
                  title: 'Near You',
                  icon: Icons.location_on_outlined,
                  codes: nearbyCodes,
                  loading: _locationLoading,
                  denied: _locationDenied,
                  locationError: _locationError,
                  currentUserId: currentUserId,
                  onRetry: _fetchPosition,
                  emptyMessage: 'No codes near your current location',
                ),
              ),

            // ── Popular Nearby (signed-in only) ───────────────────────
            if (!isGuest && popularCodes.isNotEmpty)
              SliverToBoxAdapter(
                child: _NearbySection(
                  title: 'Popular Nearby',
                  icon: Icons.trending_up_rounded,
                  codes: popularCodes,
                  loading: false,
                  denied: false,
                  locationError: false,
                  currentUserId: currentUserId,
                  emptyMessage: '',
                ),
              ),

            // ── Codes (stats + recent) or empty state ─────────────────
            codesAsync.when(
              loading: () => const SliverFillRemaining(
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text('Failed to load codes: $e',
                      style: const TextStyle(color: AppTheme.danger)),
                ),
              ),
              data: (codes) {
                if (codes.isEmpty) {
                  return const SliverFillRemaining(
                    hasScrollBody: false,
                    child: _EmptyState(),
                  );
                }
                return SliverList(
                  delegate: SliverChildListDelegate([
                    _StatsBar(codes: codes),
                    _RecentCodesSection(
                      codes: codes.take(5).toList(),
                      currentUserId: currentUserId,
                    ),
                    const SizedBox(height: 100),
                  ]),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Reusable nearby section (Near You + Popular Nearby)
// ---------------------------------------------------------------------------
class _NearbySection extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<QrCodeModel>? codes;
  final bool loading;
  final bool denied;
  final bool locationError;
  final String? currentUserId;
  final VoidCallback? onRetry;
  final String emptyMessage;

  const _NearbySection({
    required this.title,
    required this.icon,
    required this.codes,
    required this.loading,
    required this.denied,
    required this.locationError,
    required this.currentUserId,
    required this.emptyMessage,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Row(
            children: [
              Icon(icon, size: 18, color: AppTheme.textSecondary),
              const SizedBox(width: 4),
              Text(title, style: Theme.of(context).textTheme.titleMedium),
            ],
          ),
        ),
        if (loading)
          const SizedBox(
            height: 120,
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          )
        else if (denied)
          _NearbyPlaceholder(
            icon: Icons.location_off_outlined,
            message: 'Enable location to see nearby codes',
          )
        else if (locationError)
          GestureDetector(
            onTap: onRetry,
            child: _NearbyPlaceholder(
              icon: Icons.refresh,
              message: 'Could not get location — tap to retry',
            ),
          )
        else if (codes == null || codes!.isEmpty)
          _NearbyPlaceholder(
            icon: Icons.explore_outlined,
            message: emptyMessage,
          )
        else
          SizedBox(
            height: 160,
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
              scrollDirection: Axis.horizontal,
              itemCount: codes!.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (_, i) => _QrCard(
                code: codes![i],
                isOwner: codes![i].userId == currentUserId,
              ),
            ),
          ),
        const SizedBox(height: 28),
      ],
    );
  }
}

class _NearbyPlaceholder extends StatelessWidget {
  final IconData icon;
  final String message;
  const _NearbyPlaceholder({required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 90,
      margin: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: AppTheme.textSecondary, size: 20),
          const SizedBox(width: 10),
          Text(message, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Stats bar
// ---------------------------------------------------------------------------
class _StatsBar extends StatelessWidget {
  final List<QrCodeModel> codes;
  const _StatsBar({required this.codes});

  @override
  Widget build(BuildContext context) {
    final scanned = codes.where((c) => c.source == QrCodeSource.scanned).length;
    final created = codes.where((c) => c.source == QrCodeSource.created).length;

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.15)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _StatItem(value: '${codes.length}', label: 'Total'),
          _VerticalDivider(),
          _StatItem(value: '$scanned', label: 'Scanned'),
          _VerticalDivider(),
          _StatItem(value: '$created', label: 'Created'),
        ],
      ),
    );
  }
}

class _VerticalDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) =>
      Container(width: 1, height: 32, color: Theme.of(context).colorScheme.outlineVariant);
}

class _StatItem extends StatelessWidget {
  final String value;
  final String label;
  const _StatItem({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: AppTheme.primary,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 2),
        Text(label, style: Theme.of(context).textTheme.bodyMedium),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Recent codes section — user's own codes only
// ---------------------------------------------------------------------------
class _RecentCodesSection extends StatelessWidget {
  final List<QrCodeModel> codes;
  final String? currentUserId;
  const _RecentCodesSection({required this.codes, required this.currentUserId});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 4, 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Recent', style: Theme.of(context).textTheme.titleMedium),
              TextButton(
                onPressed: () => context.go('/library'),
                child: const Text('See all'),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 160,
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
            scrollDirection: Axis.horizontal,
            itemCount: codes.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (_, i) => _QrCard(
              code: codes[i],
              isOwner: true, // Recent only shows the user's own codes
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// QR code card — used by Near You, Popular, and Recent
// ---------------------------------------------------------------------------
class _QrCard extends StatelessWidget {
  final QrCodeModel code;
  final bool isOwner;

  const _QrCard({required this.code, required this.isOwner});

  Color _hexToColor(String hex) {
    final clean = hex.replaceAll('#', '');
    return Color(int.parse('FF$clean', radix: 16));
  }

  @override
  Widget build(BuildContext context) {
    final fgColor = _hexToColor(code.foregroundColor);
    final bgColor = _hexToColor(code.backgroundColor);

    return GestureDetector(
      onTap: () => context.push('/detail/${code.id}'),
      child: Container(
        width: 140,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // QR preview
            Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: QrImageView(
                  data: code.content,
                  version: QrVersions.auto,
                  size: 84,
                  backgroundColor: bgColor,
                  eyeStyle: QrEyeStyle(eyeShape: QrEyeShape.square, color: fgColor),
                  dataModuleStyle: QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: fgColor),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              code.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                _TypeBadge(type: code.type),
                const SizedBox(width: 4),
                _OwnerBadge(isOwner: isOwner),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Ownership badge
// ---------------------------------------------------------------------------
class _OwnerBadge extends StatelessWidget {
  final bool isOwner;
  const _OwnerBadge({required this.isOwner});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: isOwner
            ? AppTheme.primary.withValues(alpha: 0.15)
            : Colors.grey.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isOwner
              ? AppTheme.primary.withValues(alpha: 0.35)
              : Colors.grey.withValues(alpha: 0.35),
          width: 0.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isOwner ? Icons.person_rounded : Icons.public_rounded,
            size: 9,
            color: isOwner ? AppTheme.primary : AppTheme.textSecondary,
          ),
          const SizedBox(width: 2),
          Text(
            isOwner ? 'Mine' : 'Public',
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w600,
              color: isOwner ? AppTheme.primary : AppTheme.textSecondary,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Type badge
// ---------------------------------------------------------------------------
class _TypeBadge extends StatelessWidget {
  final QrCodeType type;
  const _TypeBadge({required this.type});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        type.name.toUpperCase(),
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: AppTheme.primary,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Full empty state
// ---------------------------------------------------------------------------
class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(40, 60, 40, 40),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.qr_code_2_rounded, size: 44, color: AppTheme.primary),
          ),
          const SizedBox(height: 24),
          Text('No QR codes yet',
              style: Theme.of(context).textTheme.titleLarge, textAlign: TextAlign.center),
          const SizedBox(height: 10),
          Text(
            'Tap the + button below to scan or create your first QR code.',
            style: Theme.of(context).textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
