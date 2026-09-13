import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../core/constants/app_constants.dart';
import '../../core/location/map_privacy.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/qr_code_model.dart';

class NearbyCodesMap extends StatefulWidget {
  final List<QrCodeModel> codes;
  final double? userLat;
  final double? userLng;
  final bool interactive;
  final double height;
  final bool loading;
  final bool locationDenied;
  final bool locationError;
  final bool clusterPins;
  final String? ownerUserId;
  final VoidCallback? onEnableLocation;

  const NearbyCodesMap({
    super.key,
    required this.codes,
    this.userLat,
    this.userLng,
    this.interactive = false,
    this.height = 180,
    this.loading = false,
    this.locationDenied = false,
    this.locationError = false,
    this.clusterPins = false,
    this.ownerUserId,
    this.onEnableLocation,
  });

  @override
  State<NearbyCodesMap> createState() => _NearbyCodesMapState();
}

class _NearbyCodesMapState extends State<NearbyCodesMap> {
  final _mapController = MapController();
  var _mapReady = false;
  var _zoom = 13.0;
  DateTime? _lastRebuild;

  static const _minZoom = 3.0;
  static const _maxZoom = 18.0;

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(NearbyCodesMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    final lat = widget.userLat;
    final lng = widget.userLng;
    if (!_mapReady || lat == null || lng == null) return;
    if (oldWidget.userLat == lat && oldWidget.userLng == lng) return;
    _mapController.move(LatLng(lat, lng), _mapController.camera.zoom);
  }

  void _zoomBy(double delta) {
    if (!_mapReady) return;
    final camera = _mapController.camera;
    final next = (camera.zoom + delta).clamp(_minZoom, _maxZoom);
    _mapController.move(camera.center, next);
  }

  void _recenter() {
    if (!_mapReady || widget.userLat == null || widget.userLng == null) return;
    _mapController.move(
      LatLng(widget.userLat!, widget.userLng!),
      _mapController.camera.zoom,
    );
  }

  void _onCameraChanged(MapPosition position) {
    if (!widget.clusterPins) return;
    final zoom = position.zoom;
    if (zoom == null) return;
    final now = DateTime.now();
    final zoomJump = (zoom - _zoom).abs() >= 0.4;
    final panAtStreet = zoom >= 14 &&
        _lastRebuild != null &&
        now.difference(_lastRebuild!) > const Duration(milliseconds: 280);
    if (!zoomJump && !panAtStreet && _lastRebuild != null) return;
    _lastRebuild = now;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _zoom = zoom);
    });
  }

  List<Marker> _buildPins(BuildContext context) {
    final points = <({QrCodeModel code, LatLng point})>[];
    for (final code in widget.codes) {
      final lat = code.mapLat;
      final lng = code.mapLng;
      if (lat == null || lng == null) continue;
      points.add((code: code, point: publicMapPoint(lat, lng)));
    }

    if (!widget.clusterPins) {
      return [for (final item in points) _dotMarker(item)];
    }

    var visible = points;
    if (_mapReady && _zoom >= 14) {
      final bounds = _mapController.camera.visibleBounds;
      visible = points.where((item) => bounds.contains(item.point)).toList();
      if (visible.length > 120) visible = visible.take(120).toList();
    }

    final cell = clusterCellDegrees(_zoom);
    if (cell <= 0) {
      return [for (final item in visible) _dotMarker(item)];
    }

    final groups = <String, List<({QrCodeModel code, LatLng point})>>{};
    for (final item in visible) {
      final key =
          '${(item.point.latitude / cell).round()}_${(item.point.longitude / cell).round()}';
      groups.putIfAbsent(key, () => []).add(item);
    }

    return groups.values.map((group) {
      final first = group.first;
      if (group.length == 1) return _dotMarker(first);
      final lat = group.fold<double>(0, (s, e) => s + e.point.latitude) /
          group.length;
      final lng = group.fold<double>(0, (s, e) => s + e.point.longitude) /
          group.length;
      final center = LatLng(lat, lng);
      final allMine = widget.ownerUserId != null &&
          group.every((e) => e.code.userId == widget.ownerUserId);
      return Marker(
        point: center,
        width: 40,
        height: 40,
        child: GestureDetector(
          onTap: () {
            if (!_mapReady) return;
            final next = (_zoom + 2).clamp(_minZoom, _maxZoom);
            _mapController.move(center, next);
          },
          child: _ClusterBubble(
            count: group.length,
            color: allMine ? AppTheme.mapOwn : AppTheme.mapPublic,
          ),
        ),
      );
    }).toList();
  }

  Marker _dotMarker(({QrCodeModel code, LatLng point}) item) {
    final mine =
        widget.ownerUserId != null && item.code.userId == widget.ownerUserId;
    return Marker(
      point: item.point,
      width: 18,
      height: 18,
      child: GestureDetector(
        onTap: () => context.push('/detail/${item.code.id}'),
        child: _CodeDot(
          color: mine ? AppTheme.mapOwn : AppTheme.mapPublic,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.loading) {
      return _frame(
        context,
        const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    if (widget.locationDenied || widget.locationError) {
      return _frame(
        context,
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                widget.locationDenied
                    ? Icons.location_off_outlined
                    : Icons.refresh,
                color: AppTheme.textSecondary,
              ),
              const SizedBox(height: 8),
              Text(
                widget.locationDenied
                    ? 'Allow location to see places near you'
                    : 'Could not get your location',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              if (widget.onEnableLocation != null) ...[
                const SizedBox(height: 8),
                TextButton(
                  onPressed: widget.onEnableLocation,
                  child: Text(
                    widget.locationDenied ? 'Enable location' : 'Try again',
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }

    final token = AppConstants.mapboxAccessToken;
    if (token.isEmpty) {
      return _frame(
        context,
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'Map not configured. Add a MAPBOX_ACCESS_TOKEN dart-define.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final pins = _buildPins(context);

    final hasUser = widget.userLat != null && widget.userLng != null;
    final center = hasUser
        ? LatLng(widget.userLat!, widget.userLng!)
        : (pins.isNotEmpty ? pins.first.point : const LatLng(39.8283, -98.5795));

    final map = FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: center,
        initialZoom: hasUser ? 13 : 4,
        minZoom: _minZoom,
        maxZoom: _maxZoom,
        interactionOptions: InteractionOptions(
          flags: widget.interactive ? InteractiveFlag.all : InteractiveFlag.none,
        ),
        onMapReady: () {
          _mapReady = true;
          if (widget.clusterPins) setState(() {});
        },
        onPositionChanged: (position, _) => _onCameraChanged(position),
      ),
      children: [
        TileLayer(
          urlTemplate:
              'https://api.mapbox.com/styles/v1/mapbox/streets-v12/tiles/{z}/{x}/{y}?access_token={access_token}',
          additionalOptions: {'access_token': token},
          userAgentPackageName: 'dev.gamelogic.qrvault',
          tileSize: 512,
          zoomOffset: -1,
        ),
        MarkerLayer(markers: pins),
        if (hasUser)
          MarkerLayer(markers: [
            Marker(
              point: LatLng(widget.userLat!, widget.userLng!),
              width: 18,
              height: 18,
              child: Container(
                decoration: BoxDecoration(
                  color: AppTheme.primary,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
              ),
            ),
          ]),
      ],
    );

    if (widget.interactive) {
      return LayoutBuilder(
        builder: (context, constraints) {
          final size = MediaQuery.sizeOf(context);
          final width = constraints.maxWidth.isFinite
              ? constraints.maxWidth
              : size.width;
          final height = constraints.maxHeight.isFinite
              ? constraints.maxHeight
              : size.height;
          return SizedBox(
            width: width,
            height: height,
            child: Stack(
              children: [
                map,
                Positioned(
                  right: 16,
                  bottom: 16,
                  child: SafeArea(
                    child: _MapControls(
                      onZoomIn: () => _zoomBy(1),
                      onZoomOut: () => _zoomBy(-1),
                      onRecenter: hasUser ? _recenter : null,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        height: widget.height,
        child: Stack(
          children: [
            map,
            Positioned.fill(
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => context.push('/map', extra: {
                    if (widget.userLat != null) 'lat': widget.userLat,
                    if (widget.userLng != null) 'lng': widget.userLng,
                  }),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _frame(BuildContext context, Widget child) {
    if (widget.interactive) {
      return SizedBox.expand(child: Center(child: child));
    }
    return Container(
      height: widget.height,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: child,
    );
  }
}

class _CodeDot extends StatelessWidget {
  final Color color;
  const _CodeDot({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(
          color: color == AppTheme.mapPublic ? AppTheme.primary : Colors.white,
          width: 2,
        ),
      ),
    );
  }
}

class _ClusterBubble extends StatelessWidget {
  final int count;
  final Color color;
  const _ClusterBubble({required this.count, required this.color});

  @override
  Widget build(BuildContext context) {
    final onPublic = color == AppTheme.mapPublic;
    return Container(
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(
          color: onPublic ? AppTheme.primary : Colors.white,
          width: 2,
        ),
      ),
      child: Text(
        count > 99 ? '99+' : '$count',
        style: TextStyle(
          color: onPublic ? AppTheme.primary : Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _MapControls extends StatelessWidget {
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback? onRecenter;

  const _MapControls({
    required this.onZoomIn,
    required this.onZoomOut,
    this.onRecenter,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Zoom in',
            onPressed: onZoomIn,
            icon: const Icon(Icons.add),
          ),
          Divider(height: 1, color: scheme.outlineVariant),
          IconButton(
            tooltip: 'Zoom out',
            onPressed: onZoomOut,
            icon: const Icon(Icons.remove),
          ),
          if (onRecenter != null) ...[
            Divider(height: 1, color: scheme.outlineVariant),
            IconButton(
              tooltip: 'My location',
              onPressed: onRecenter,
              icon: const Icon(Icons.my_location),
            ),
          ],
        ],
      ),
    );
  }
}
