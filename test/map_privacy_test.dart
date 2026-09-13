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
}
