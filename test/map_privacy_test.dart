import 'package:flutter_test/flutter_test.dart';
import 'package:qrvault/core/location/map_privacy.dart';

void main() {
  test('publicMapPoint snaps to a ~150m grid', () {
    final a = publicMapPoint(41.123456, -80.987654);
    final b = publicMapPoint(41.123500, -80.987600);
    expect(a.latitude, b.latitude);
    expect(a.longitude, b.longitude);
  });

  test('cluster cells get coarser as zoom decreases', () {
    expect(clusterCellDegrees(16), 0);
    expect(clusterCellDegrees(13) < clusterCellDegrees(8), isTrue);
  });

  test('same public point stays one pin at max zoom', () {
    final home = publicMapPoint(41.1234, -80.9876);
    final items = [
      for (var i = 0; i < 6; i++) ('code$i', home),
    ];
    final clusters = clusterMapPins(items, zoom: 18);
    expect(clusters, hasLength(1));
    expect(clusters.single.items, hasLength(6));
    expect(clusters.single.samePublicPoint, isTrue);
  });

  test('nearby public points merge at city zoom and split when close', () {
    final a = publicMapPoint(41.10, -80.10);
    final b = publicMapPoint(41.40, -80.40);
    final items = [('a', a), ('b', b)];
    final far = clusterMapPins(items, zoom: 4);
    expect(far, hasLength(1));
    expect(far.single.samePublicPoint, isFalse);
    final close = clusterMapPins(items, zoom: 16);
    expect(close, hasLength(2));
  });
}
