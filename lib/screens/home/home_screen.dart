import 'dart:math' as math;

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

// Haversine distance in km using dart:math for accuracy.
double _haversineKm(double lat1, double lon1, double lat2, double lon2) {
  const r = 6371.0;
  final dLat = (lat2 - lat1) * math.pi / 180;
  final dLon = (lon2 - lon1) * math.pi / 180;
  final a = math.pow(math.sin(dLat / 2), 2) +
      math.cos(lat1 * math.pi / 180) *
          math.cos(lat2 * math.pi / 180) *
          math.pow(math.sin(dLon / 2), 2);
  return r * 2 * math.asin(math.sqrt(a));
}

// ---------------------------------------------------------------------------
// Home Screen
// ---------------------------------------------------------------------------
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  // We only store the user's position — nearby filtering happens in build()
  // so it always has access to the fully-loaded qrCodesProvider data.
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
        if (mounted) {
          setState(() {
            _locationDenied = true;
            _locationLoading = false;
          });
        }
        return;
      }

      // Use last known position first — instant, no timeout risk.
      // Fall back to a live fix only when no cached position exists.
      Position? position = await Geolocator.getLastKnownPosition();
      position ??= await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 20),
        ),
      );

      if (mounted) {
        setState(() {
          _userPosition = position;
          _locationLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _userPosition = null;
          _locationLoading = false;
          _locationError = true;
        });
      }
    }
  }

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  /// Returns a first-name suffix like " Ethan", or empty string if unknown.
  String _nameSuffix() {
    final user = Supabase.instance.client.auth.currentUser;
    final fullName = user?.userMetadata?['full_name'] as String?;
    if (fullName != null && fullName.isNotEmpty) {
      return ', ${fullName.split(' ').first}';
    }
    final email = user?.email ?? '';
    final prefix = email.split('@').first;
    if (prefix.isNotEmpty) return ', $prefix';
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final codesAsync = ref.watch(qrCodesProvider);
    // Watch radius so Near You updates immediately when slider changes.
    final radiusKm = ref.watch(nearbyRadiusProvider) * 1.60934;

    // Compute nearby codes reactively — codes are guaranteed to be loaded here.
    List<QrCodeModel>? nearbyCodes;
    if (!_locationLoading && !_locationDenied && _userPosition != null) {
      final allCodes = codesAsync.asData?.value ?? [];
      nearbyCodes = allCodes.where((qr) {
        final lat = qr.lastScannedLat ?? qr.firstScannedLat;
        final lng = qr.lastScannedLng ?? qr.firstScannedLng;
        if (lat == null || lng == null) return false;
        return _haversineKm(
              _userPosition!.latitude,
              _userPosition!.longitude,
              lat,
              lng,
            ) <=
            radiusKm;
      }).toList();
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('QRVault'),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await Future.wait([
            ref.read(qrCodesProvider.notifier).refresh(),
            _fetchPosition(),
          ]);
        },
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            // ── Greeting ────────────────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                child: Text(
                  '${_greeting()}${_nameSuffix()}',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
              ),
            ),

            // ── Near You ────────────────────────────────────────────────────
            SliverToBoxAdapter(
              child: _NearYouSection(
                codes: nearbyCodes,
                loading: _locationLoading,
                denied: _locationDenied,
                locationError: _locationError,
                onRetry: _fetchPosition,
              ),
            ),

            // ── Codes (stats + recent) or empty state ────────────────────
            codesAsync.when(
              loading: () => const SliverFillRemaining(
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text(
                    'Failed to load codes: $e',
                    style: const TextStyle(color: AppTheme.danger),
                  ),
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
                    _RecentCodesSection(codes: codes.take(5).toList()),
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
// Near You section
// ---------------------------------------------------------------------------
class _NearYouSection extends StatelessWidget {
  final List<QrCodeModel>? codes;
  final bool loading;
  final bool denied;
  final bool locationError;
  final VoidCallback? onRetry;

  const _NearYouSection({
    required this.codes,
    required this.loading,
    required this.denied,
    this.locationError = false,
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
              const Icon(
                Icons.location_on_outlined,
                size: 18,
                color: AppTheme.textSecondary,
              ),
              const SizedBox(width: 4),
              Text(
                'Near You',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
          ),
        ),
        if (loading)
          const SizedBox(
            height: 120,
            child: Center(
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          )
        else if (denied)
          _NearYouPlaceholder(
            icon: Icons.location_off_outlined,
            message: 'Enable location to see nearby codes',
          )
        else if (locationError)
          GestureDetector(
            onTap: onRetry,
            child: _NearYouPlaceholder(
              icon: Icons.refresh,
              message: 'Could not get location — tap to retry',
            ),
          )
        else if (codes == null || codes!.isEmpty)
          _NearYouPlaceholder(
            icon: Icons.explore_outlined,
            message: 'No saved codes near your current location',
          )
        else
          SizedBox(
            height: 160,
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
              scrollDirection: Axis.horizontal,
              itemCount: codes!.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (_, i) => _QrCard(code: codes![i]),
            ),
          ),
        const SizedBox(height: 28),
      ],
    );
  }
}

class _NearYouPlaceholder extends StatelessWidget {
  final IconData icon;
  final String message;

  const _NearYouPlaceholder({required this.icon, required this.message});

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
    final scanned =
        codes.where((c) => c.source == QrCodeSource.scanned).length;
    final created =
        codes.where((c) => c.source == QrCodeSource.created).length;

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppTheme.primary.withValues(alpha: 0.15),
        ),
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
// Recent Codes section
// ---------------------------------------------------------------------------
class _RecentCodesSection extends StatelessWidget {
  final List<QrCodeModel> codes;

  const _RecentCodesSection({required this.codes});

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
              Text(
                'Recent',
                style: Theme.of(context).textTheme.titleMedium,
              ),
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
            itemBuilder: (_, i) => _QrCard(code: codes[i]),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// QR code card — shared by Near You and Recent
// ---------------------------------------------------------------------------
class _QrCard extends StatelessWidget {
  final QrCodeModel code;

  const _QrCard({required this.code});

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
                  eyeStyle: QrEyeStyle(
                    eyeShape: QrEyeShape.square,
                    color: fgColor,
                  ),
                  dataModuleStyle: QrDataModuleStyle(
                    dataModuleShape: QrDataModuleShape.square,
                    color: fgColor,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            // Label
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
            // Type badge
            _TypeBadge(type: code.type),
          ],
        ),
      ),
    );
  }
}

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
// Full empty state — first-time users with zero codes
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
            child: const Icon(
              Icons.qr_code_2_rounded,
              size: 44,
              color: AppTheme.primary,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'No QR codes yet',
            style: Theme.of(context).textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
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
