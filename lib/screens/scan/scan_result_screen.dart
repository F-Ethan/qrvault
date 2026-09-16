import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';

import '../../data/models/qr_code_model.dart';
import '../../data/qr_content.dart';
import '../../data/qr_payload.dart';
import '../../data/repositories/qr_code_repository.dart';
import '../../providers/qr_code_providers.dart';
import '../../providers/settings_providers.dart';
import 'qr_payload_editor.dart';

class ScanResultScreen extends ConsumerStatefulWidget {
  final String content;

  const ScanResultScreen({super.key, required this.content});

  @override
  ConsumerState<ScanResultScreen> createState() => _ScanResultScreenState();
}

class _ScanResultScreenState extends ConsumerState<ScanResultScreen> {
  late bool _isPublic;
  late final QrCodeType _type;
  late String _effectiveContent;
  bool _hasDate = false;
  bool _hasParts = false;
  List<PayloadPartConfig> _payloadParts = const [];

  bool _lookupDone = false;
  bool _busy = false;
  QrCodeModel? _matched;
  bool _queuedOpen = false;
  bool _queuedSave = false;
  bool _didLaunch = false;

  double? _lat;
  double? _lng;
  String? _place;

  @override
  void initState() {
    super.initState();
    _type = detectQrType(widget.content);
    _isPublic = defaultIsPublic(_type);
    _effectiveContent = widget.content;
    final parsed = QrPayloadBlueprint.parse(widget.content);
    _hasDate = parsed.hasDateParts;
    _payloadParts = suggestedPayloadConfigs(
      widget.content,
      hasDate: parsed.hasDateParts,
      hasParts: false,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _lookup();
      _captureLocation();
    });
  }

  Future<void> _captureLocation() async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 8),
        ),
      );
      String? place;
      try {
        final placemarks = await placemarkFromCoordinates(
          position.latitude,
          position.longitude,
        );
        if (placemarks.isNotEmpty) {
          final p = placemarks.first;
          final parts = [p.locality, p.administrativeArea]
              .where((s) => s != null && s.isNotEmpty)
              .map((s) => s!)
              .toList();
          if (parts.isNotEmpty) place = parts.join(', ');
        }
      } catch (_) {}
      if (mounted) {
        setState(() {
          _lat = position.latitude;
          _lng = position.longitude;
          _place = place;
        });
      }
    } catch (_) {}
  }

  Future<void> _lookup() async {
    if (ref.read(guestModeProvider) ||
        Supabase.instance.client.auth.currentUser == null) {
      if (mounted) setState(() => _lookupDone = true);
      return;
    }
    try {
      final existing =
          await ref.read(qrCodeRepositoryProvider).findExisting(widget.content);
      if (!mounted) return;
      setState(() {
        _matched = existing;
        _lookupDone = true;
        if (existing != null) {
          _hasDate = existing.hasDate || _hasDate;
          _hasParts = existing.hasParts;
          if (existing.payloadParts.isNotEmpty) {
            _payloadParts = existing.payloadParts;
          }
        }
      });
    } catch (_) {
      if (mounted) setState(() => _lookupDone = true);
    }
    await _flushIntent();
  }

  Future<void> _flushIntent() async {
    if (!_lookupDone || (!_queuedOpen && !_queuedSave)) return;
    await _applyIntent(open: _queuedOpen, save: _queuedSave);
  }

  Future<void> _applyIntent({required bool open, required bool save}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      if (open) await _launch();

      if (ref.read(guestModeProvider) ||
          Supabase.instance.client.auth.currentUser == null) {
        if (save && mounted) _promptGuest();
        return;
      }

      if (_matched != null) {
        final recorded = await ref.read(qrCodesProvider.notifier).recordScan(
              content: _matched!.content,
              lat: _lat,
              lng: _lng,
              place: _place,
              saveMembership: save && _matched!.userId !=
                  Supabase.instance.client.auth.currentUser?.id,
            );
        if (recorded.code != null && mounted) {
          setState(() => _matched = recorded.code);
        }
        return;
      }

      if (save) {
        await _insertNew();
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _queuedOpen = false;
          _queuedSave = false;
        });
      }
    }
  }

  Future<void> _insertNew() async {
    final user = Supabase.instance.client.auth.currentUser!;
    final label = autoQrLabel(widget.content, _type);
    final now = DateTime.now();
    final model = QrCodeModel(
      id: const Uuid().v4(),
      userId: user.id,
      label: label.isNotEmpty ? label : _type.name,
      type: _type,
      content: widget.content,
      source: QrCodeSource.scanned,
      isPublic: _isPublic,
      hasDate: _hasDate,
      hasParts: _hasParts,
      payloadTemplate: _hasDate
          ? datePayloadTemplate(widget.content, _payloadParts)
          : null,
      payloadParts: _payloadParts,
      scanCount: 1,
      publicScanCount: 1,
      myScanCount: 1,
      hasMembership: true,
      firstScannedAt: now,
      lastScannedAt: now,
      firstScannedLat: _lat,
      firstScannedLng: _lng,
      firstScannedPlace: _place,
      lastScannedLat: _lat,
      lastScannedLng: _lng,
      lastScannedPlace: _place,
      createdAt: now,
      updatedAt: now,
    );
    await ref.read(qrCodesProvider.notifier).add(model);
    final list = ref.read(qrCodesProvider).asData?.value ?? [];
    final saved = list.where((c) => c.content == widget.content).firstOrNull;
    if (mounted) setState(() => _matched = saved ?? model);
  }

  Future<void> _launch() async {
    if (_didLaunch) return;
    final uri = Uri.tryParse(_effectiveContent);
    if (uri == null) return;
    if (await canLaunchUrl(uri)) {
      _didLaunch = true;
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  void _promptGuest() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Sign up to save',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            const Text(
              'Create a free account to keep this code in your library.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () {
                Navigator.pop(context);
                context.push('/sign-up');
              },
              child: const Text('Sign Up'),
            ),
          ],
        ),
      ),
    );
  }

  void _onOpenOnly() {
    if (!_lookupDone) {
      setState(() {
        _queuedOpen = true;
        _queuedSave = false;
      });
      _launch();
      return;
    }
    _applyIntent(open: true, save: false);
  }

  void _onOpenAndSave() {
    if (!_lookupDone) {
      setState(() {
        _queuedOpen = true;
        _queuedSave = true;
      });
      _launch();
      return;
    }
    _applyIntent(open: true, save: true);
  }

  void _onSaveOnly() {
    if (!_lookupDone) {
      setState(() => _queuedSave = true);
      return;
    }
    _applyIntent(open: false, save: true);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final matched = _matched;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Scanned'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        children: [
          Center(
            child: Container(
              width: 200,
              height: 200,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: scheme.outlineVariant),
              ),
              child: QrImageView(
                data: _effectiveContent,
                size: 176,
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            matched?.displayLabel ?? autoQrLabel(widget.content, _type),
            style: Theme.of(context).textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          SelectableText(
            _effectiveContent,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 20),
          if (_hasDate || _hasParts)
            QrPayloadEditor(
              content: widget.content,
              hasDate: _hasDate,
              hasParts: _hasParts,
              configs: _payloadParts,
              onContentChanged: (v) => setState(() => _effectiveContent = v),
            ),
          if (_hasDate || _hasParts) const SizedBox(height: 20),
          InputDecorator(
            decoration: const InputDecoration(
              labelText: 'Visibility',
              border: OutlineInputBorder(),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<bool>(
                value: matched?.isPublic ?? _isPublic,
                isExpanded: true,
                items: const [
                  DropdownMenuItem(value: true, child: Text('Public')),
                  DropdownMenuItem(value: false, child: Text('Private')),
                ],
                onChanged: matched != null
                    ? null
                    : (v) {
                        if (v == null) return;
                        setState(() => _isPublic = v);
                      },
              ),
            ),
          ),
          if (matched != null) ...[
            const SizedBox(height: 8),
            Text(
              'This code already exists. Visibility stays as the owner set it.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          if (matched == null && _type == QrCodeType.url) ...[
            const SizedBox(height: 8),
            PayloadFlagToggles(
              hasDate: _hasDate,
              hasParts: _hasParts,
              onHasDate: (v) => setState(() {
                _hasDate = v;
                _payloadParts = v
                    ? addSuggestedPayloadConfigs(
                        widget.content,
                        _payloadParts,
                        dates: true,
                        parts: false,
                      )
                    : _payloadParts
                        .where((c) => c.kind != PayloadPartKind.date)
                        .toList();
              }),
              onHasParts: (v) => setState(() {
                _hasParts = v;
                _payloadParts = v
                    ? addSuggestedPayloadConfigs(
                        widget.content,
                        _payloadParts,
                        dates: false,
                        parts: true,
                      )
                    : _payloadParts
                        .where((c) => c.kind == PayloadPartKind.date)
                        .toList();
              }),
            ),
            PayloadSegmentPicker(
              content: widget.content,
              hasDate: _hasDate,
              hasParts: _hasParts,
              configs: _payloadParts,
              onChanged: (next) => setState(() => _payloadParts = next),
            ),
          ],
          const SizedBox(height: 12),
          if (!_lookupDone)
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: LinearProgressIndicator(),
            ),
          if (isLaunchableQr(_type)) ...[
            FilledButton(
              onPressed: _busy ? null : _onOpenAndSave,
              child: const Text('Open and save'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: _busy ? null : _onOpenOnly,
              child: const Text('Open only'),
            ),
          ] else
            FilledButton(
              onPressed: _busy ? null : _onSaveOnly,
              child: const Text('Save to library'),
            ),
          if (matched != null) ...[
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: () => context.push('/detail/${matched.id}'),
              child: const Text('View card'),
            ),
          ],
        ],
      ),
    );
  }
}
