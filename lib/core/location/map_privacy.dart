import 'package:latlong2/latlong.dart';

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
