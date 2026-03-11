import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';

import '../../core/theme/app_theme.dart';
import '../../data/models/qr_code_model.dart';
import '../../providers/qr_code_providers.dart';
import '../../providers/settings_providers.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------
QrCodeType _detectType(String content) {
  if (content.startsWith('WIFI:')) return QrCodeType.wifi;
  if (content.startsWith('BEGIN:VCARD')) return QrCodeType.contact;
  if (content.startsWith('mailto:')) return QrCodeType.email;
  if (content.startsWith('http://') || content.startsWith('https://')) {
    return QrCodeType.url;
  }
  return QrCodeType.text;
}

// FIDO:/... QR codes are CTAP Cross-Device Authentication codes — they can
// only be handled by the system camera (passkey ceremony), not opened as URLs.
bool _isFidoContent(String content) =>
    content.toUpperCase().startsWith('FIDO:');

String _autoLabel(String content, QrCodeType type) {
  return switch (type) {
    QrCodeType.url =>
      Uri.tryParse(content)?.host.replaceAll('www.', '') ?? content,
    QrCodeType.wifi =>
      RegExp(r'S:([^;]+)').firstMatch(content)?.group(1) ?? 'WiFi',
    QrCodeType.contact =>
      RegExp(r'FN:(.+)').firstMatch(content)?.group(1)?.trim() ?? 'Contact',
    QrCodeType.email =>
      content.replaceFirst('mailto:', '').split('?').first,
    QrCodeType.text =>
      content.length > 30 ? '${content.substring(0, 30)}…' : content,
  };
}

// ---------------------------------------------------------------------------
// Scan Screen
// ---------------------------------------------------------------------------
class ScanScreen extends ConsumerStatefulWidget {
  const ScanScreen({super.key});

  @override
  ConsumerState<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends ConsumerState<ScanScreen>
    with WidgetsBindingObserver {
  late final MobileScannerController _controller;
  bool _detected = false;
  double _zoomScale = 0.0;
  double _baseZoomScale = 0.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = MobileScannerController(
      detectionSpeed: DetectionSpeed.noDuplicates,
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        if (!_detected) _controller.start();
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
        _controller.stop();
      default:
        break;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Detection handler
  // ---------------------------------------------------------------------------
  void _onDetect(BarcodeCapture capture) {
    if (_detected) return;
    final raw = capture.barcodes.firstOrNull?.rawValue;
    if (raw == null || raw.isEmpty) return;

    _detected = true;
    _controller.stop();

    // FIDO passkey QR codes must be handled by the system camera — intercept
    // before the save sheet and show a plain warning instead.
    if (_isFidoContent(raw)) {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (_) => _FidoWarningSheet(
          onScanAgain: () {
            setState(() => _detected = false);
            _controller.start();
          },
        ),
      ).whenComplete(() {
        // Reset if user swiped the sheet away without pressing Scan Again.
        if (mounted && _detected) {
          setState(() => _detected = false);
          _controller.start();
        }
      });
      return;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _ConfirmSheet(
        raw: raw,
        onScanAgain: () {
          setState(() => _detected = false);
          _controller.start();
        },
        onSave: (label) => _saveCode(raw, label),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Save
  // ---------------------------------------------------------------------------
  Future<void> _saveCode(String content, String label) async {
    // Guests cannot save — show sign-up prompt instead
    if (ref.read(guestModeProvider)) {
      if (!mounted) return;
      showModalBottomSheet(
        context: context,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (_) => _GuestSaveSheet(
          onSignUp: () {
            Navigator.pop(context);
            context.push('/sign-up');
          },
          onDismiss: () {
            Navigator.pop(context);
            setState(() => _detected = false);
            _controller.start();
          },
        ),
      ).whenComplete(() {
        if (mounted && _detected) {
          setState(() => _detected = false);
          _controller.start();
        }
      });
      return;
    }

    try {
      final user = Supabase.instance.client.auth.currentUser!;
      final type = _detectType(content);
      final resolvedLabel =
          label.isNotEmpty ? label : _autoLabel(content, type);

      // Try to capture location at scan time; fail silently if unavailable.
      double? lat;
      double? lng;
      String? place;
      try {
        var permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied) {
          permission = await Geolocator.requestPermission();
        }
        if (permission != LocationPermission.denied &&
            permission != LocationPermission.deniedForever) {
          final position = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.medium,
              timeLimit: Duration(seconds: 8),
            ),
          );
          lat = position.latitude;
          lng = position.longitude;

          final placemarks = await placemarkFromCoordinates(lat, lng);
          if (placemarks.isNotEmpty) {
            final p = placemarks.first;
            final parts = [p.locality, p.administrativeArea]
                .where((s) => s != null && s.isNotEmpty)
                .map((s) => s!)
                .toList();
            if (parts.isNotEmpty) place = parts.join(', ');
          }
        }
      } catch (_) {
        // Location unavailable — save without it.
      }

      final qrCode = QrCodeModel(
        id: const Uuid().v4(),
        userId: user.id,
        label: resolvedLabel.isNotEmpty ? resolvedLabel : type.name,
        type: type,
        content: content,
        source: QrCodeSource.scanned,
        scanCount: 1,
        firstScannedAt: DateTime.now(),
        lastScannedAt: DateTime.now(),
        firstScannedLat: lat,
        firstScannedLng: lng,
        firstScannedPlace: place,
        lastScannedLat: lat,
        lastScannedLng: lng,
        lastScannedPlace: place,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await ref.read(qrCodesProvider.notifier).add(qrCode);

      if (mounted) context.pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save: $e'),
            backgroundColor: AppTheme.danger,
          ),
        );
        setState(() => _detected = false);
        _controller.start();
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        // Pinch-to-zoom: track baseline at start, update on scale change.
        onScaleStart: (_) => _baseZoomScale = _zoomScale,
        onScaleUpdate: (details) {
          if (details.pointerCount < 2) return;
          final zoom =
              (_baseZoomScale + (details.scale - 1.0) * 0.6).clamp(0.0, 1.0);
          if ((zoom - _zoomScale).abs() > 0.004) {
            setState(() => _zoomScale = zoom);
            _controller.setZoomScale(zoom);
          }
        },
        child: Stack(
          children: [
            // ── Camera ────────────────────────────────────────────────────
            MobileScanner(
              controller: _controller,
              onDetect: _onDetect,
              errorBuilder: (context, error) => _CameraError(
                error: error,
                onClose: () => context.pop(),
              ),
            ),

            // ── Semi-transparent overlay + corner brackets ────────────────
            const _ScanOverlay(),

            // ── Top controls ──────────────────────────────────────────────
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _OverlayButton(
                      icon: Icons.close_rounded,
                      onTap: () => context.pop(),
                    ),
                    _OverlayButton(
                      icon: Icons.flash_on_rounded,
                      onTap: () => _controller.toggleTorch(),
                    ),
                  ],
                ),
              ),
            ),

            // ── Zoom slider ───────────────────────────────────────────────
            Positioned(
              bottom: 130,
              left: 32,
              right: 32,
              child: _ZoomControl(
                zoom: _zoomScale,
                onChanged: (val) {
                  setState(() => _zoomScale = val);
                  _controller.setZoomScale(val);
                },
              ),
            ),

            // ── Bottom instruction ─────────────────────────────────────────
            Positioned(
              bottom: 72,
              left: 0,
              right: 0,
              child: Column(
                children: [
                  const Icon(
                    Icons.qr_code_scanner_rounded,
                    color: Colors.white54,
                    size: 22,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Point at any QR code to scan',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.8),
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Overlay — dark surround + white corner brackets
// ---------------------------------------------------------------------------
class _ScanOverlay extends StatelessWidget {
  const _ScanOverlay();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _OverlayPainter(),
      child: const SizedBox.expand(),
    );
  }
}

class _OverlayPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const side = 260.0;
    final rect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2 - 40),
      width: side,
      height: side,
    );
    const radius = Radius.circular(16);

    // Dark surround
    canvas.drawPath(
      Path.combine(
        PathOperation.difference,
        Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height)),
        Path()..addRRect(RRect.fromRectAndRadius(rect, radius)),
      ),
      Paint()..color = Colors.black.withValues(alpha: 0.55),
    );

    // Corner brackets
    const len = 28.0;
    final p = Paint()
      ..color = Colors.white
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    void drawCorner(Offset a, Offset corner, Offset b) {
      canvas.drawPath(
        Path()
          ..moveTo(a.dx, a.dy)
          ..lineTo(corner.dx, corner.dy)
          ..lineTo(b.dx, b.dy),
        p,
      );
    }

    // Top-left
    drawCorner(
      Offset(rect.left, rect.top + len),
      rect.topLeft,
      Offset(rect.left + len, rect.top),
    );
    // Top-right
    drawCorner(
      Offset(rect.right - len, rect.top),
      rect.topRight,
      Offset(rect.right, rect.top + len),
    );
    // Bottom-left
    drawCorner(
      Offset(rect.left, rect.bottom - len),
      rect.bottomLeft,
      Offset(rect.left + len, rect.bottom),
    );
    // Bottom-right
    drawCorner(
      Offset(rect.right - len, rect.bottom),
      rect.bottomRight,
      Offset(rect.right, rect.bottom - len),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ---------------------------------------------------------------------------
// Translucent icon button for the camera overlay
// ---------------------------------------------------------------------------
class _OverlayButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _OverlayButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: Colors.white, size: 22),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// FIDO warning sheet — shown when a passkey QR code is detected
// ---------------------------------------------------------------------------
class _FidoWarningSheet extends StatelessWidget {
  final VoidCallback onScanAgain;

  const _FidoWarningSheet({required this.onScanAgain});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        24,
        16,
        24,
        MediaQuery.of(context).viewInsets.bottom + 40,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Icon + title
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.key_rounded,
                    color: Colors.amber, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Passkey QR Code',
                        style: Theme.of(context).textTheme.titleMedium),
                    Text('Cannot be opened in QRVault',
                        style: Theme.of(context).textTheme.bodyMedium),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Info box
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.amber.withValues(alpha: 0.08),
              border:
                  Border.all(color: Colors.amber.withValues(alpha: 0.35)),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              'This is a passkey sign-in QR code (FIDO2). It can only be '
              'processed by your iPhone\'s built-in Camera app — open Camera, '
              'point it at the QR code on the other screen, and follow the '
              'sign-in prompt.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          const SizedBox(height: 20),

          // Open Camera button
          FilledButton.icon(
            onPressed: () async {
              final uri = Uri.parse('camera-switcher:');
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri);
              }
            },
            icon: const Icon(Icons.camera_alt_rounded),
            label: const Text('Open Camera App'),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.amber,
              foregroundColor: Colors.black87,
            ),
          ),
          const SizedBox(height: 10),

          // Scan another
          OutlinedButton(
            onPressed: () {
              Navigator.pop(context);
              onScanAgain();
            },
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(double.infinity, 52),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              side: const BorderSide(color: AppTheme.border),
              foregroundColor: AppTheme.textSecondary,
            ),
            child: const Text('Scan another code'),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Confirmation bottom sheet — shown after a code is detected
// ---------------------------------------------------------------------------
class _ConfirmSheet extends StatefulWidget {
  final String raw;
  final VoidCallback onScanAgain;
  final Future<void> Function(String label) onSave;

  const _ConfirmSheet({
    required this.raw,
    required this.onScanAgain,
    required this.onSave,
  });

  @override
  State<_ConfirmSheet> createState() => _ConfirmSheetState();
}

class _ConfirmSheetState extends State<_ConfirmSheet> {
  late final TextEditingController _labelCtrl;
  late final QrCodeType _type;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _type = _detectType(widget.raw);
    _labelCtrl = TextEditingController(
      text: _autoLabel(widget.raw, _type),
    );
  }

  @override
  void dispose() {
    _labelCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        24,
        16,
        24,
        MediaQuery.of(context).viewInsets.bottom + 40,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          const SizedBox(height: 20),

          // QR preview + type + raw content
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: QrImageView(
                  data: widget.raw,
                  version: QrVersions.auto,
                  size: 88,
                  backgroundColor: Colors.white,
                  eyeStyle: const QrEyeStyle(
                    eyeShape: QrEyeShape.square,
                    color: Colors.black,
                  ),
                  dataModuleStyle: const QrDataModuleStyle(
                    dataModuleShape: QrDataModuleShape.square,
                    color: Colors.black,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Code detected!',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 6),
                    _TypeBadge(type: _type),
                    const SizedBox(height: 8),
                    Text(
                      widget.raw,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          // Label field
          TextField(
            controller: _labelCtrl,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Label',
              hintText: 'Give this code a name',
              prefixIcon: Icon(Icons.label_outline_rounded),
            ),
          ),

          const SizedBox(height: 16),

          // Save button
          FilledButton(
            onPressed: _saving
                ? null
                : () async {
                    setState(() => _saving = true);
                    Navigator.pop(context);
                    await widget.onSave(_labelCtrl.text.trim());
                  },
            child: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                : const Text('Save to Library'),
          ),

          const SizedBox(height: 10),

          // Scan another button
          OutlinedButton(
            onPressed: _saving
                ? null
                : () {
                    Navigator.pop(context);
                    widget.onScanAgain();
                  },
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(double.infinity, 52),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              side: const BorderSide(color: AppTheme.border),
              foregroundColor: AppTheme.textSecondary,
            ),
            child: const Text('Scan another'),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Camera error screen — shown when camera is unavailable or permission denied
// ---------------------------------------------------------------------------
class _CameraError extends StatelessWidget {
  final MobileScannerException error;
  final VoidCallback onClose;

  const _CameraError({required this.error, required this.onClose});

  bool get _isPermissionDenied =>
      error.errorCode == MobileScannerErrorCode.permissionDenied;

  String get _title => _isPermissionDenied
      ? 'Camera permission denied'
      : 'Camera unavailable';

  String get _message => _isPermissionDenied
      ? 'QRVault needs access to your camera to scan QR codes. Please enable it in Settings.'
      : 'No camera was found on this device. Scanning is only available on a physical iPhone.';

  IconData get _icon => _isPermissionDenied
      ? Icons.no_photography_outlined
      : Icons.videocam_off_outlined;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: SafeArea(
        child: Column(
          children: [
            // Close button
            Align(
              alignment: Alignment.topLeft,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: _OverlayButton(
                  icon: Icons.close_rounded,
                  onTap: onClose,
                ),
              ),
            ),

            // Error content
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(_icon, color: Colors.white54, size: 64),
                    const SizedBox(height: 20),
                    Text(
                      _title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _message,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.65),
                        fontSize: 15,
                        height: 1.5,
                      ),
                    ),
                    if (_isPermissionDenied) ...[
                      const SizedBox(height: 28),
                      GestureDetector(
                        onTap: () => launchUrl(
                          Uri.parse('app-settings:'),
                          mode: LaunchMode.externalApplication,
                        ),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 24, vertical: 14),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Text(
                            'Open Settings',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Zoom control — slider + zoom level label, shown at bottom of camera view
// ---------------------------------------------------------------------------
class _ZoomControl extends StatelessWidget {
  final double zoom;
  final ValueChanged<double> onChanged;

  const _ZoomControl({required this.zoom, required this.onChanged});

  // Map 0.0–1.0 to a display string like "1.0×" – "5.0×".
  String get _label => '${(1.0 + zoom * 4.0).toStringAsFixed(1)}×';

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // 1× reset tap
        GestureDetector(
          onTap: () => onChanged(0.0),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '1×',
              style: TextStyle(
                color: Colors.white.withValues(alpha: zoom == 0 ? 0.45 : 1.0),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        // Slider
        Expanded(
          child: SliderTheme(
            data: SliderThemeData(
              trackHeight: 2.5,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
              activeTrackColor: Colors.white,
              inactiveTrackColor: Colors.white24,
              thumbColor: Colors.white,
              overlayColor: Colors.white24,
            ),
            child: Slider(
              value: zoom,
              min: 0.0,
              max: 1.0,
              onChanged: onChanged,
            ),
          ),
        ),
        const SizedBox(width: 8),
        // Zoom level label
        Container(
          width: 44,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            _label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Guest save sheet — shown when a guest tries to save a QR code
// ---------------------------------------------------------------------------
class _GuestSaveSheet extends StatelessWidget {
  final VoidCallback onSignUp;
  final VoidCallback onDismiss;

  const _GuestSaveSheet({required this.onSignUp, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        24,
        16,
        24,
        MediaQuery.of(context).viewInsets.bottom + 40,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 24),

          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.save_outlined,
                color: AppTheme.primary, size: 32),
          ),
          const SizedBox(height: 16),

          Text(
            'Sign up to save QR codes',
            style: Theme.of(context).textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            "It's free! Create an account to build your personal QR code library.",
            style: Theme.of(context).textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),

          FilledButton(
            onPressed: onSignUp,
            child: const Text('Create a Free Account'),
          ),
          const SizedBox(height: 10),
          TextButton(
            onPressed: onDismiss,
            child: const Text('Continue without saving'),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Type badge — matches style from other screens
// ---------------------------------------------------------------------------
class _TypeBadge extends StatelessWidget {
  final QrCodeType type;

  const _TypeBadge({required this.type});

  String get _label => switch (type) {
        QrCodeType.url => 'URL',
        QrCodeType.text => 'TEXT',
        QrCodeType.wifi => 'WIFI',
        QrCodeType.contact => 'CONTACT',
        QrCodeType.email => 'EMAIL',
      };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        _label,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: AppTheme.primary,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
