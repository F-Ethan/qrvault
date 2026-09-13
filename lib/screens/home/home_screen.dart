import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/location/device_location.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/qr_code_model.dart';
import '../../providers/qr_code_providers.dart';
import '../../providers/settings_providers.dart';
import 'nearby_codes_map.dart';

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
    if (_userPosition == null) {
      setState(() {
        _locationLoading = true;
        _locationDenied = false;
        _locationError = false;
      });
    }

    try {
      await resolveDeviceLocation(
        onUpdate: (position) {
          if (!mounted) return;
          setState(() {
            _userPosition = position;
            _locationLoading = false;
            _locationDenied = false;
            _locationError = false;
          });
        },
        onFailure: ({required bool denied}) {
          if (!mounted) return;
          setState(() {
            _locationDenied = denied;
            _locationError = !denied;
            _locationLoading = false;
          });
        },
      );
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

  Future<void> _enableLocation() async {
    await openLocationSettingsForPermission();
    await _fetchPosition();
  }

  Map<String, double> get _mapExtra => {
        if (_userPosition != null) 'lat': _userPosition!.latitude,
        if (_userPosition != null) 'lng': _userPosition!.longitude,
      };

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

    // Fetch public nearby codes from all users (signed-in and guest).
    List<QrCodeModel> publicNearby = const [];
    if (!_locationLoading && !_locationDenied && _userPosition != null) {
      final nearbyAsync = ref.watch(nearbyPublicProvider((
        lat: _userPosition!.latitude,
        lng: _userPosition!.longitude,
        radiusKm: radiusKm,
      )));
      publicNearby = nearbyAsync.asData?.value ?? [];
    }

    // Near You = user's own codes with nearby location + public codes from others.
    List<QrCodeModel>? nearbyCodes;
    if (!_locationLoading && !_locationDenied && _userPosition != null) {
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

    final miles = ref.watch(nearbyRadiusProvider);
    final milesLabel = miles == miles.roundToDouble()
        ? '${miles.round()} ${miles.round() == 1 ? 'mile' : 'miles'}'
        : '${miles.toStringAsFixed(1)} miles';
    final nearbyList = nearbyCodes ?? const <QrCodeModel>[];
    final showNearbyStrip = !_locationLoading &&
        !_locationDenied &&
        !_locationError &&
        nearbyList.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          isGuest ? 'QRVault' : '${_greeting()}${_nameSuffix()}',
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await _fetchPosition();
          if (!isGuest) {
            await ref.read(qrCodesProvider.notifier).refresh();
          }
        },
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            if (isGuest)
              const SliverToBoxAdapter(child: _GuestBanner()),

            codesAsync.when(
              loading: () => isGuest
                  ? const SliverToBoxAdapter(child: SizedBox.shrink())
                  : const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(24, 16, 24, 8),
                        child: Center(
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      ),
                    ),
              error: (e, _) => SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
                  child: Text(
                    'Could not load your library.',
                    style: TextStyle(color: AppTheme.danger),
                  ),
                ),
              ),
              data: (codes) {
                if (isGuest) {
                  return const SliverToBoxAdapter(child: SizedBox.shrink());
                }
                if (codes.isEmpty) {
                  return const SliverToBoxAdapter(child: _GetStartedCard());
                }
                return SliverToBoxAdapter(
                  child: _RecentCodesSection(
                    codes: codes.take(5).toList(),
                    totalCount: codes.length,
                  ),
                );
              },
            ),

            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 8, 10),
                child: Row(
                  children: [
                    Text('Near you',
                        style: Theme.of(context).textTheme.titleMedium),
                    const Spacer(),
                    TextButton(
                      onPressed: () => context.push('/map', extra: _mapExtra),
                      child: const Text('Map'),
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                child: NearbyCodesMap(
                  codes: nearbyList.isNotEmpty ? nearbyList : publicNearby,
                  ownerUserId: currentUserId,
                  userLat: _userPosition?.latitude,
                  userLng: _userPosition?.longitude,
                  height: 152,
                  loading: _locationLoading,
                  locationDenied: _locationDenied,
                  locationError: _locationError,
                  onEnableLocation: _locationDenied
                      ? _enableLocation
                      : (_locationError ? _fetchPosition : null),
                ),
              ),
            ),
            if (showNearbyStrip)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: _CodeStrip(
                    codes: nearbyList,
                    currentUserId: currentUserId,
                  ),
                ),
              )
            else if (!_locationLoading &&
                !_locationDenied &&
                !_locationError)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
                  child: Text(
                    'Nothing public within $milesLabel. Scan a code here to drop a pin.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              ),

            const SliverToBoxAdapter(child: SizedBox(height: 100)),
          ],
        ),
      ),
    );
  }
}

class _GuestBanner extends StatelessWidget {
  const _GuestBanner();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Browsing as a guest',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'Sign in to save scans and build a library.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                TextButton(
                  onPressed: () => context.push('/sign-in'),
                  child: const Text('Sign in'),
                ),
                TextButton(
                  onPressed: () => context.push('/sign-up'),
                  child: const Text('Create account'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _GetStartedCard extends StatelessWidget {
  const _GetStartedCard();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Your library is empty',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Scan something around you, or create a code to share.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                TextButton(
                  onPressed: () => context.push('/scan'),
                  child: const Text('Scan'),
                ),
                TextButton(
                  onPressed: () => context.push('/create'),
                  child: const Text('Create'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CodeStrip extends StatelessWidget {
  final List<QrCodeModel> codes;
  final String? currentUserId;
  final bool showOwner;

  const _CodeStrip({
    required this.codes,
    required this.currentUserId,
    this.showOwner = true,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 160,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        scrollDirection: Axis.horizontal,
        itemCount: codes.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (_, i) => _QrCard(
          code: codes[i],
          isOwner: codes[i].userId == currentUserId,
          showOwner: showOwner,
        ),
      ),
    );
  }
}

class _RecentCodesSection extends StatelessWidget {
  final List<QrCodeModel> codes;
  final int totalCount;

  const _RecentCodesSection({required this.codes, required this.totalCount});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 8, 8),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Your codes',
                        style: Theme.of(context).textTheme.titleMedium),
                    Text(
                      '$totalCount in your library',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: () => context.go('/library'),
                child: const Text('See all'),
              ),
            ],
          ),
        ),
        _CodeStrip(codes: codes, currentUserId: null, showOwner: false),
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
  final bool showOwner;

  const _QrCard({
    required this.code,
    required this.isOwner,
    this.showOwner = true,
  });

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
              code.displayLabel,
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
                if (showOwner) ...[
                  const SizedBox(width: 4),
                  _OwnerBadge(isOwner: isOwner),
                ],
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
