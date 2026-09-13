import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/location/device_location.dart';
import '../../data/models/qr_code_model.dart';
import '../../providers/qr_code_providers.dart';
import 'nearby_codes_map.dart';

class MapScreen extends ConsumerStatefulWidget {
  final double? initialLat;
  final double? initialLng;

  const MapScreen({super.key, this.initialLat, this.initialLng});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  Position? _position;
  late bool _loading;

  @override
  void initState() {
    super.initState();
    final seeded = widget.initialLat != null && widget.initialLng != null;
    _loading = !seeded;
    if (seeded) {
      _position = Position(
        latitude: widget.initialLat!,
        longitude: widget.initialLng!,
        timestamp: DateTime.now(),
        accuracy: 0,
        altitude: 0,
        altitudeAccuracy: 0,
        heading: 0,
        headingAccuracy: 0,
        speed: 0,
        speedAccuracy: 0,
      );
    }
    _load();
  }

  Future<void> _load() async {
    try {
      await resolveDeviceLocation(
        onUpdate: (position) {
          if (!mounted) return;
          setState(() {
            _position = position;
            _loading = false;
          });
        },
        onFailure: ({required bool denied}) {
          if (!mounted) return;
          setState(() => _loading = false);
        },
      );
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final publicAsync = ref.watch(allPublicProvider);
    final mine = ref.watch(qrCodesProvider).asData?.value ?? [];
    final me = Supabase.instance.client.auth.currentUser?.id;
    final byId = <String, QrCodeModel>{
      for (final c in publicAsync.asData?.value ?? [])
        if (c.mapLat != null && c.mapLng != null) c.id: c,
    };
    for (final c in mine) {
      if (c.mapLat != null && c.mapLng != null) byId[c.id] = c;
    }
    final codes = byId.values.toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Explore map')),
      body: NearbyCodesMap(
        codes: codes,
        ownerUserId: me,
        userLat: _position?.latitude,
        userLng: _position?.longitude,
        interactive: true,
        clusterPins: true,
        loading: publicAsync.isLoading && codes.isEmpty && _loading,
      ),
    );
  }
}
