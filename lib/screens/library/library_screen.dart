import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme/app_theme.dart';
import '../../data/models/qr_code_model.dart';
import '../../data/repositories/qr_code_repository.dart' show haversineKm;
import '../../providers/qr_code_providers.dart';
import '../../providers/settings_providers.dart';

// ---------------------------------------------------------------------------
// Filter enum — "all" + one value per QrCodeType
// Names match QrCodeType.name so filtering is a simple string compare.
// ---------------------------------------------------------------------------
enum _Filter { all, url, text, wifi, contact, email }

// ---------------------------------------------------------------------------
// Library Screen
// ---------------------------------------------------------------------------
class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  _Filter _activeFilter = _Filter.all;
  String _searchQuery = '';
  bool _showAllCodes = false; // false = My Codes, true = All Public
  bool _localOnly = true; // when true, "All Public" is restricted to radius
  late final TextEditingController _searchController;

  // Public codes are only ever shown within the user's nearby radius by
  // default — location is fetched lazily, the first time "All Public" is
  // selected. Searching always widens to every public code (see build()).
  Position? _userPosition;
  bool _locationLoading = false;
  bool _locationDenied = false;
  bool _locationError = false;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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

  // Orders public codes closest-first. Codes without location data (or when
  // the user's own position isn't known) sort last, by scan count.
  List<QrCodeModel> _sortNearbyFirst(List<QrCodeModel> codes) {
    final position = _userPosition;
    if (position == null) return codes;

    double? distanceKm(QrCodeModel c) {
      final lat = c.lastScannedLat ?? c.firstScannedLat;
      final lng = c.lastScannedLng ?? c.firstScannedLng;
      if (lat == null || lng == null) return null;
      return haversineKm(position.latitude, position.longitude, lat, lng);
    }

    final sorted = [...codes];
    sorted.sort((a, b) {
      final da = distanceKm(a);
      final db = distanceKm(b);
      if (da == null && db == null) return b.scanCount.compareTo(a.scanCount);
      if (da == null) return 1;
      if (db == null) return -1;
      return da.compareTo(db);
    });
    return sorted;
  }

  List<QrCodeModel> _applyFilters(List<QrCodeModel> all) {
    var result = all;

    if (_activeFilter != _Filter.all) {
      result = result.where((c) => c.type.name == _activeFilter.name).toList();
    }

    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      result = result
          .where((c) =>
              c.displayLabel.toLowerCase().contains(q) ||
              c.content.toLowerCase().contains(q))
          .toList();
    }

    return result;
  }

  String _filterLabel(_Filter f) => switch (f) {
        _Filter.all => 'All',
        _Filter.url => 'URL',
        _Filter.text => 'Text',
        _Filter.wifi => 'WiFi',
        _Filter.contact => 'Contact',
        _Filter.email => 'Email',
      };

  @override
  Widget build(BuildContext context) {
    final myCodesAsync = ref.watch(qrCodesProvider);
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;

    // Searching always widens to every public code, regardless of the
    // "Local only" toggle — you should be able to find a specific code
    // even if it's not near you.
    final searchingPublic = _showAllCodes && _searchQuery.isNotEmpty;
    final restrictedToNearby = _showAllCodes && _localOnly && !searchingPublic;

    // Only the radius-restricted view actually requires location.
    if (restrictedToNearby && (_locationDenied || _locationError)) {
      return Scaffold(
        appBar: AppBar(title: const Text('Library')),
        body: _LocationRequired(
          isError: _locationError,
          onRetry: _fetchPosition,
        ),
      );
    }

    final AsyncValue<List<QrCodeModel>> sourceAsync;
    if (_showAllCodes) {
      if (restrictedToNearby) {
        if (_userPosition == null) {
          sourceAsync = const AsyncValue.loading();
        } else {
          final radiusKm = ref.watch(nearbyRadiusProvider) * 1.60934;
          sourceAsync = ref.watch(nearbyPublicProvider((
            lat: _userPosition!.latitude,
            lng: _userPosition!.longitude,
            radiusKm: radiusKm,
          )));
        }
      } else {
        sourceAsync = ref.watch(allPublicProvider);
      }
    } else {
      sourceAsync = myCodesAsync;
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Library')),
      body: sourceAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Text('Failed to load: $e',
              style: const TextStyle(color: AppTheme.danger)),
        ),
        data: (codes) {
          final ordered = _showAllCodes ? _sortNearbyFirst(codes) : codes;
          final filtered = _applyFilters(ordered);

          return RefreshIndicator(
            onRefresh: () async {
              if (_showAllCodes) {
                if (restrictedToNearby && _userPosition != null) {
                  final radiusKm = ref.read(nearbyRadiusProvider) * 1.60934;
                  ref.invalidate(nearbyPublicProvider((
                    lat: _userPosition!.latitude,
                    lng: _userPosition!.longitude,
                    radiusKm: radiusKm,
                  )));
                } else if (_userPosition == null) {
                  await _fetchPosition();
                } else {
                  ref.invalidate(allPublicProvider);
                }
              } else {
                await ref.read(qrCodesProvider.notifier).refresh();
              }
            },
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                // ── Search bar ─────────────────────────────────────────────
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                    child: TextField(
                      controller: _searchController,
                      onChanged: (v) => setState(() => _searchQuery = v),
                      decoration: InputDecoration(
                        hintText: _showAllCodes
                            ? 'Search all public codes…'
                            : 'Search my codes…',
                        prefixIcon: const Icon(Icons.search_rounded,
                            color: AppTheme.textSecondary),
                        suffixIcon: _searchQuery.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear_rounded),
                                color: AppTheme.textSecondary,
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() => _searchQuery = '');
                                },
                              )
                            : null,
                      ),
                    ),
                  ),
                ),

                // ── My / All toggle ─────────────────────────────────────────
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(
                          value: false,
                          label: Text('My Codes'),
                          icon: Icon(Icons.person_rounded, size: 16),
                        ),
                        ButtonSegment(
                          value: true,
                          label: Text('All Public'),
                          icon: Icon(Icons.public_rounded, size: 16),
                        ),
                      ],
                      selected: {_showAllCodes},
                      onSelectionChanged: (s) {
                        setState(() {
                          _showAllCodes = s.first;
                          _activeFilter = _Filter.all;
                          _searchQuery = '';
                          _searchController.clear();
                        });
                        if (_showAllCodes &&
                            _userPosition == null &&
                            !_locationLoading &&
                            !_locationDenied) {
                          _fetchPosition();
                        }
                      },
                    ),
                  ),
                ),

                // ── Local only toggle (All Public mode) ─────────────────────
                if (_showAllCodes)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: Row(
                        children: [
                          const Icon(Icons.near_me_outlined,
                              size: 16, color: AppTheme.textSecondary),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Local only',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ),
                          Switch(
                            value: _localOnly,
                            onChanged: (v) {
                              setState(() => _localOnly = v);
                              if (v &&
                                  _userPosition == null &&
                                  !_locationLoading &&
                                  !_locationDenied) {
                                _fetchPosition();
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                  ),

                // ── Filter chips ────────────────────────────────────────────
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: 40,
                    child: ListView(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      scrollDirection: Axis.horizontal,
                      children: _Filter.values.map((f) {
                        final isActive = f == _activeFilter;
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: FilterChip(
                            label: Text(_filterLabel(f)),
                            selected: isActive,
                            showCheckmark: false,
                            onSelected: (_) =>
                                setState(() => _activeFilter = f),
                            backgroundColor: Theme.of(context)
                                .colorScheme
                                .surfaceContainerLow,
                            selectedColor:
                                AppTheme.primary.withValues(alpha: 0.12),
                            side: BorderSide(
                              color: isActive
                                  ? AppTheme.primary
                                  : Theme.of(context)
                                      .colorScheme
                                      .outlineVariant,
                            ),
                            labelStyle: TextStyle(
                              fontSize: 13,
                              color: isActive
                                  ? AppTheme.primary
                                  : AppTheme.textSecondary,
                              fontWeight: isActive
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),

                // ── Result count ────────────────────────────────────────────
                if (codes.isNotEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                      child: Text(
                        '${filtered.length} code${filtered.length == 1 ? '' : 's'}',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                  ),

                // ── Grid / empty states ─────────────────────────────────────
                if (codes.isEmpty)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: _EmptyState(isSearch: false),
                  )
                else if (filtered.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _EmptyState(
                      isSearch: _searchQuery.isNotEmpty ||
                          _activeFilter != _Filter.all,
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                    sliver: SliverGrid.builder(
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                        childAspectRatio: 0.88,
                      ),
                      itemCount: filtered.length,
                      itemBuilder: (_, i) => _LibraryCard(
                        code: filtered[i],
                        isOwner: filtered[i].userId == currentUserId,
                        showOwnerBadge: _showAllCodes,
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shown instead of the grid when "All Public" needs location access —
// public codes are only ever surfaced within the user's nearby radius.
// ---------------------------------------------------------------------------
class _LocationRequired extends StatelessWidget {
  final bool isError;
  final VoidCallback onRetry;

  const _LocationRequired({required this.isError, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isError ? Icons.error_outline_rounded : Icons.location_off_outlined,
              size: 40,
              color: AppTheme.textSecondary,
            ),
            const SizedBox(height: 16),
            Text(
              isError
                  ? "Couldn't get your location. Try again."
                  : 'Enable location to see public codes near you',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: onRetry,
              child: const Text('Enable Location'),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Grid card
// ---------------------------------------------------------------------------
class _LibraryCard extends StatelessWidget {
  final QrCodeModel code;
  final bool isOwner;
  final bool showOwnerBadge;

  const _LibraryCard({
    required this.code,
    this.isOwner = true,
    this.showOwnerBadge = false,
  });

  Color _hexToColor(String hex) {
    final clean = hex.replaceAll('#', '');
    return Color(int.parse('FF$clean', radix: 16));
  }

  @override
  Widget build(BuildContext context) {
    final fgColor = _hexToColor(code.foregroundColor);
    final bgColor = _hexToColor(code.backgroundColor);
    final place = code.lastScannedPlace ?? code.firstScannedPlace;

    return GestureDetector(
      onTap: () => context.push('/detail/${code.id}'),
      child: Container(
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
                  size: 100,
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

            const SizedBox(height: 10),

            // Label
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

            // Type badge + ownership badge + optional place
            Row(
              children: [
                _TypeBadge(type: code.type),
                if (showOwnerBadge) ...[
                  const SizedBox(width: 4),
                  _OwnerBadge(isOwner: isOwner),
                ],
                if (place != null) ...[
                  const SizedBox(width: 6),
                  const Icon(
                    Icons.location_on_outlined,
                    size: 10,
                    color: AppTheme.textSecondary,
                  ),
                  const SizedBox(width: 2),
                  Expanded(
                    child: Text(
                      place,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 10,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ),
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
// Type badge — same style as Home screen
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
// Empty state
// ---------------------------------------------------------------------------
class _EmptyState extends StatelessWidget {
  final bool isSearch;

  const _EmptyState({required this.isSearch});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(40),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isSearch ? Icons.search_off_rounded : Icons.qr_code_2_rounded,
              size: 40,
              color: AppTheme.primary,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            isSearch ? 'No results' : 'No QR codes yet',
            style: Theme.of(context).textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),
          Text(
            isSearch
                ? 'Try adjusting your search or filter.'
                : 'Tap the + button below to scan or create your first QR code.',
            style: Theme.of(context).textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
