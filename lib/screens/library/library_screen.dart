import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/theme/app_theme.dart';
import '../../data/models/qr_code_model.dart';
import '../../providers/qr_code_providers.dart';

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
  late final TextEditingController _searchController;

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

  List<QrCodeModel> _applyFilters(List<QrCodeModel> all) {
    var result = all;

    if (_activeFilter != _Filter.all) {
      result =
          result.where((c) => c.type.name == _activeFilter.name).toList();
    }

    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      result = result
          .where((c) =>
              c.label.toLowerCase().contains(q) ||
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
    final codesAsync = ref.watch(qrCodesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Library'),
      ),
      body: codesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Text(
            'Failed to load: $e',
            style: const TextStyle(color: AppTheme.danger),
          ),
        ),
        data: (codes) {
          final filtered = _applyFilters(codes);

          return RefreshIndicator(
            onRefresh: () => ref.read(qrCodesProvider.notifier).refresh(),
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
                        hintText: 'Search codes…',
                        prefixIcon: const Icon(
                          Icons.search_rounded,
                          color: AppTheme.textSecondary,
                        ),
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
                            backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
                            selectedColor:
                                AppTheme.primary.withValues(alpha: 0.12),
                            side: BorderSide(
                              color: isActive
                                  ? AppTheme.primary
                                  : Theme.of(context).colorScheme.outlineVariant,
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
                        '${filtered.length} '
                        'code${filtered.length == 1 ? '' : 's'}',
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
                      itemBuilder: (_, i) => _LibraryCard(code: filtered[i]),
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
// Grid card
// ---------------------------------------------------------------------------
class _LibraryCard extends StatelessWidget {
  final QrCodeModel code;

  const _LibraryCard({required this.code});

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

            // Type badge + optional place
            Row(
              children: [
                _TypeBadge(type: code.type),
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
