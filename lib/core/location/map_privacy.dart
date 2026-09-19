import 'package:latlong2/latlong.dart';

/// A set of codes drawn as one map pin.
class MapPinCluster<T> {
  const MapPinCluster({
    required this.point,
    required this.items,
    required this.samePublicPoint,
  });

  final LatLng point;
  final List<T> items;

  /// True when every item snapped to the same public grid cell (~150 m).
  /// Those pins must stay stacked as one marker at every zoom.
  final bool samePublicPoint;
}

String publicPointKey(LatLng point) =>
    '${point.latitude.toStringAsFixed(6)}_${point.longitude.toStringAsFixed(6)}';

/// Group snapped public points. Same coordinate is always one pin, even at
/// max zoom. At lower zooms, nearby cells merge until the user zooms in.
List<MapPinCluster<T>> clusterMapPins<T>(
  Iterable<(T, LatLng)> items, {
  required double zoom,
}) {
  final list = items.toList();
  if (list.isEmpty) return const [];

  final byPoint = <String, List<(T, LatLng)>>{};
  for (final item in list) {
    byPoint.putIfAbsent(publicPointKey(item.$2), () => []).add(item);
  }

  final cell = clusterCellDegrees(zoom);
  if (cell <= 0) {
    return [
      for (final group in byPoint.values)
        MapPinCluster(
          point: group.first.$2,
          items: [for (final e in group) e.$1],
          samePublicPoint: true,
        ),
    ];
  }

  final byCell = <String, List<(T, LatLng)>>{};
  for (final item in list) {
    final point = item.$2;
    final key =
        '${(point.latitude / cell).round()}_${(point.longitude / cell).round()}';
    byCell.putIfAbsent(key, () => []).add(item);
  }

  return [
    for (final group in byCell.values)
      MapPinCluster(
        point: LatLng(
          group.fold<double>(0, (s, e) => s + e.$2.latitude) / group.length,
          group.fold<double>(0, (s, e) => s + e.$2.longitude) / group.length,
        ),
        items: [for (final e in group) e.$1],
        samePublicPoint: group.every(
          (e) => publicPointKey(e.$2) == publicPointKey(group.first.$2),
        ),
      ),
  ];
}

/// Snap public map pins to a ~150 m grid so a scan at home does not
/// publish a street address. Exact coords stay in the database for the owner.
LatLng publicMapPoint(double lat, double lng) {
  const step = 0.0015;
  return LatLng(
    (lat / step).round() * step,
    (lng / step).round() * step,
  );
}

/// Grid size in degrees for clustering at a given zoom.
double clusterCellDegrees(double zoom) {
  if (zoom >= 15) return 0;
  if (zoom >= 13) return 0.015;
  if (zoom >= 11) return 0.05;
  if (zoom >= 8) return 0.2;
  return 1.0;
}
