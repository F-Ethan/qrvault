import 'package:geolocator/geolocator.dart';

Future<void> resolveDeviceLocation({
  required void Function(Position position) onUpdate,
  required void Function({required bool denied}) onFailure,
}) async {
  if (!await Geolocator.isLocationServiceEnabled()) {
    onFailure(denied: true);
    return;
  }

  var permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
  }
  if (permission == LocationPermission.denied ||
      permission == LocationPermission.deniedForever) {
    onFailure(denied: true);
    return;
  }

  final lastKnown = await Geolocator.getLastKnownPosition();

  try {
    final current = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.medium,
        timeLimit: Duration(seconds: 12),
      ),
    );
    onUpdate(current);
  } catch (_) {
    if (lastKnown != null) {
      onUpdate(lastKnown);
    } else {
      onFailure(denied: false);
    }
  }
}

Future<void> openLocationSettingsForPermission() async {
  final permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.deniedForever) {
    await Geolocator.openAppSettings();
    return;
  }
  if (!await Geolocator.isLocationServiceEnabled()) {
    await Geolocator.openLocationSettings();
  }
}
