import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_theme.dart';
import '../../data/models/qr_code_model.dart';
import '../../providers/qr_code_providers.dart';

// ---------------------------------------------------------------------------
// Colour presets (same set as create screen)
// ---------------------------------------------------------------------------
const _fgPresets = [
  Color(0xFF000000),
  Color(0xFF4F46E5),
  Color(0xFF0F766E),
  Color(0xFF1D4ED8),
  Color(0xFF7C3AED),
  Color(0xFFB45309),
];

const _bgPresets = [
  Color(0xFFFFFFFF),
  Color(0xFFF9FAFB),
  Color(0xFFEEF2FF),
  Color(0xFFF0FDF4),
  Color(0xFFFFF7ED),
  Color(0xFFF0F9FF),
];

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------
Color _hexToColor(String hex) {
  final clean = hex.replaceAll('#', '');
  return Color(int.parse('FF$clean', radix: 16));
}

String _colorToHex(Color c) {
  final hex = c.toARGB32().toRadixString(16).padLeft(8, '0');
  return '#${hex.substring(2).toUpperCase()}';
}

final _dateFmt = DateFormat('MMM d, yyyy · h:mm a');

String _fmt(DateTime? dt) => dt != null ? _dateFmt.format(dt) : '—';

String _parseWifi(String content, String field) =>
    RegExp('$field:([^;]+)').firstMatch(content)?.group(1) ?? '';

String _parseVCard(String content, String field) =>
    RegExp('$field:(.+)').firstMatch(content)?.group(1)?.trim() ?? '';

// ---------------------------------------------------------------------------
// Detail Screen
// ---------------------------------------------------------------------------
class DetailScreen extends ConsumerStatefulWidget {
  final String id;

  const DetailScreen({super.key, required this.id});

  @override
  ConsumerState<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends ConsumerState<DetailScreen> {
  bool _initialized = false;
  bool _isEditing = false;
  bool _saving = false;

  late TextEditingController _labelCtrl;
  Color _fgColor = const Color(0xFF000000);
  Color _bgColor = const Color(0xFFFFFFFF);

  @override
  void initState() {
    super.initState();
    _labelCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _labelCtrl.dispose();
    super.dispose();
  }

  // Initialise editable fields from loaded code — runs once only.
  void _initFromCode(QrCodeModel code) {
    if (_initialized) return;
    _labelCtrl.text = code.label;
    _fgColor = _hexToColor(code.foregroundColor);
    _bgColor = _hexToColor(code.backgroundColor);
    _initialized = true;
  }

  void _cancelEdit(QrCodeModel code) {
    setState(() {
      _labelCtrl.text = code.label;
      _fgColor = _hexToColor(code.foregroundColor);
      _bgColor = _hexToColor(code.backgroundColor);
      _isEditing = false;
    });
  }

  Future<void> _saveEdit(QrCodeModel code) async {
    setState(() => _saving = true);
    try {
      final label = _labelCtrl.text.trim();
      await ref.read(qrCodesProvider.notifier).updateCode(
            code.copyWith(
              label: label.isNotEmpty ? label : code.label,
              foregroundColor: _colorToHex(_fgColor),
              backgroundColor: _colorToHex(_bgColor),
            ),
          );
      if (mounted) setState(() => _isEditing = false);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save: $e'),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _deleteCode(QrCodeModel code) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete code?'),
        content: Text(
          '"${code.label}" will be permanently removed from your library.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppTheme.danger),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await ref.read(qrCodesProvider.notifier).remove(code.id);
      if (mounted) context.pop();
    }
  }

  void _copy(String text, {String label = 'Copied!'}) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(label),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _launchUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.platformDefault);
    } else {
      _copy(url, label: 'URL copied (could not open browser)');
    }
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final codesAsync = ref.watch(qrCodesProvider);

    return codesAsync.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        appBar: AppBar(),
        body: Center(child: Text('Error: $e')),
      ),
      data: (codes) {
        final code = codes.where((c) => c.id == widget.id).firstOrNull;
        if (code == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const Center(child: Text('Code not found.')),
          );
        }

        _initFromCode(code);

        return Scaffold(
          appBar: AppBar(
            title: Text(
              _isEditing ? 'Edit code' : code.label,
              overflow: TextOverflow.ellipsis,
            ),
            actions: _isEditing
                ? [
                    TextButton(
                      onPressed: () => _cancelEdit(code),
                      child: const Text('Cancel'),
                    ),
                    _saving
                        ? const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 16),
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : TextButton(
                            onPressed: () => _saveEdit(code),
                            child: const Text(
                              'Save',
                              style: TextStyle(
                                color: AppTheme.primary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                  ]
                : [
                    IconButton(
                      icon: const Icon(Icons.edit_outlined),
                      onPressed: () => setState(() => _isEditing = true),
                      tooltip: 'Edit',
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.delete_outline_rounded,
                        color: AppTheme.danger,
                      ),
                      onPressed: () => _deleteCode(code),
                      tooltip: 'Delete',
                    ),
                  ],
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(0, 8, 0, 60),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Large QR code ────────────────────────────────────────────
                _buildQrSection(code),

                const SizedBox(height: 24),

                // ── Clickable URL / content action ───────────────────────────
                _buildContentAction(code),

                const SizedBox(height: 24),

                // ── Edit section: label + colours ────────────────────────────
                if (_isEditing) ...[
                  _buildEditSection(code),
                  const SizedBox(height: 24),
                ],

                // ── Details metadata ─────────────────────────────────────────
                _buildDetailsSection(code),

                const SizedBox(height: 24),

                // ── Location ─────────────────────────────────────────────────
                if (_hasLocation(code)) ...[
                  _buildLocationSection(code),
                  const SizedBox(height: 24),
                ],

                // ── Delete ───────────────────────────────────────────────────
                if (!_isEditing)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: OutlinedButton.icon(
                      onPressed: () => _deleteCode(code),
                      icon: const Icon(Icons.delete_outline_rounded,
                          color: AppTheme.danger),
                      label: const Text('Delete code'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 52),
                        foregroundColor: AppTheme.danger,
                        side: BorderSide(
                            color: AppTheme.danger.withValues(alpha: 0.4)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // QR code section
  // ---------------------------------------------------------------------------
  Widget _buildQrSection(QrCodeModel code) {
    // In edit mode show live preview with new colours; otherwise use saved.
    final fg = _isEditing ? _fgColor : _hexToColor(code.foregroundColor);
    final bg = _isEditing ? _bgColor : _hexToColor(code.backgroundColor);

    return Center(
      child: Container(
        width: 280,
        height: 280,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 20,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: QrImageView(
            data: code.content,
            version: QrVersions.auto,
            size: 280,
            backgroundColor: bg,
            eyeStyle: QrEyeStyle(eyeShape: QrEyeShape.square, color: fg),
            dataModuleStyle:
                QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: fg),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Type-specific content action
  // ---------------------------------------------------------------------------
  Widget _buildContentAction(QrCodeModel code) {
    // FIDO passkey codes cannot be opened — they require the system camera.
    if (code.content.toUpperCase().startsWith('FIDO:')) {
      return _buildFidoWarning();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: switch (code.type) {
        QrCodeType.url => _ActionTile(
            icon: Icons.open_in_browser_rounded,
            text: code.content,
            actionLabel: 'Open',
            onTap: () => _launchUrl(code.content),
            onCopy: () => _copy(code.content, label: 'URL copied'),
          ),
        QrCodeType.email => _ActionTile(
            icon: Icons.email_outlined,
            text: code.content
                .replaceFirst('mailto:', '')
                .split('?')
                .first,
            actionLabel: 'Open',
            onTap: () => _launchUrl(code.content),
            onCopy: () => _copy(code.content, label: 'Email copied'),
          ),
        QrCodeType.wifi => _buildWifiAction(code.content),
        QrCodeType.contact => _buildContactAction(code.content),
        QrCodeType.text => _ActionTile(
            icon: Icons.text_fields_rounded,
            text: code.content,
            onCopy: () => _copy(code.content, label: 'Text copied'),
          ),
      },
    );
  }

  Widget _buildFidoWarning() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.amber.withValues(alpha: 0.08),
          border: Border.all(color: Colors.amber.withValues(alpha: 0.35)),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.key_rounded, color: Colors.amber, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Passkey QR Code',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'This is a FIDO2 passkey sign-in QR code. It can only be '
              'processed by your iPhone\'s built-in Camera app — open '
              'Camera and scan the QR code on screen to sign in.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () async {
                final uri = Uri.parse('camera-switcher:');
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri);
                }
              },
              icon: const Icon(Icons.camera_alt_rounded, size: 18),
              label: const Text('Open Camera App'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(double.infinity, 44),
                foregroundColor: Colors.amber.shade700,
                side:
                    BorderSide(color: Colors.amber.withValues(alpha: 0.5)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWifiAction(String content) {
    final ssid = _parseWifi(content, 'S');
    final password = _parseWifi(content, 'P');
    final security = _parseWifi(content, 'T');

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.wifi_rounded, color: AppTheme.primary, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(ssid,
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.onSurface)),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  security,
                  style: const TextStyle(
                      fontSize: 11,
                      color: AppTheme.primary,
                      fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          if (password.isNotEmpty) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(Icons.lock_outline_rounded,
                    size: 16, color: AppTheme.textSecondary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    password,
                    style: const TextStyle(color: AppTheme.textSecondary),
                  ),
                ),
                GestureDetector(
                  onTap: () => _copy(password, label: 'Password copied'),
                  child: const Icon(Icons.copy_rounded,
                      size: 18, color: AppTheme.textSecondary),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildContactAction(String content) {
    final name = _parseVCard(content, 'FN');
    final phone = _parseVCard(content, 'TEL');
    final email = _parseVCard(content, 'EMAIL');

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.person_rounded,
                  color: AppTheme.primary, size: 20),
              const SizedBox(width: 8),
              Text(name,
                  style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onSurface)),
            ],
          ),
          if (phone.isNotEmpty) ...[
            const SizedBox(height: 10),
            _ContactRow(
              icon: Icons.phone_outlined,
              value: phone,
              onCopy: () => _copy(phone, label: 'Phone copied'),
            ),
          ],
          if (email.isNotEmpty) ...[
            const SizedBox(height: 8),
            _ContactRow(
              icon: Icons.email_outlined,
              value: email,
              onCopy: () => _copy(email, label: 'Email copied'),
            ),
          ],
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Edit section — label field + colour pickers
  // ---------------------------------------------------------------------------
  Widget _buildEditSection(QrCodeModel code) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader('EDIT'),
        _InfoCard(children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: TextField(
              controller: _labelCtrl,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Label',
                prefixIcon: Icon(Icons.label_outline_rounded),
              ),
            ),
          ),
          // Foreground colour row
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 4, 0, 12),
            child: Row(
              children: [
                SizedBox(
                  width: 90,
                  child: Text('QR code',
                      style: Theme.of(context).textTheme.bodyMedium),
                ),
                ..._fgPresets.map((c) => _ColourCircle(
                      color: c,
                      isSelected: _fgColor == c,
                      onTap: () => setState(() => _fgColor = c),
                    )),
              ],
            ),
          ),
          // Background colour row
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 4, 0, 12),
            child: Row(
              children: [
                SizedBox(
                  width: 90,
                  child: Text('Background',
                      style: Theme.of(context).textTheme.bodyMedium),
                ),
                ..._bgPresets.map((c) => _ColourCircle(
                      color: c,
                      isSelected: _bgColor == c,
                      onTap: () => setState(() => _bgColor = c),
                    )),
              ],
            ),
          ),
        ]),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Details metadata section
  // ---------------------------------------------------------------------------
  Widget _buildDetailsSection(QrCodeModel code) {
    final typeLabels = {
      QrCodeType.url: 'URL',
      QrCodeType.text: 'Text',
      QrCodeType.wifi: 'WiFi',
      QrCodeType.contact: 'Contact',
      QrCodeType.email: 'Email',
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader('DETAILS'),
        _InfoCard(children: [
          _InfoRow(
            label: 'Label',
            value: code.label,
            trailing: _isEditing
                ? null
                : GestureDetector(
                    onTap: () => setState(() => _isEditing = true),
                    child: const Icon(Icons.edit_outlined,
                        size: 16, color: AppTheme.textSecondary),
                  ),
          ),
          _InfoRow(label: 'Type', value: typeLabels[code.type] ?? code.type.name),
          _InfoRow(
            label: 'Source',
            value: code.source == QrCodeSource.scanned ? 'Scanned' : 'Created',
          ),
          _InfoRow(
            label: 'Scans',
            value: code.scanCount == 0
                ? 'Never scanned'
                : '${code.scanCount} time${code.scanCount == 1 ? '' : 's'}',
          ),
          _InfoRow(label: 'Created', value: _fmt(code.createdAt)),
          if (code.lastScannedAt != null)
            _InfoRow(
              label: 'Last scanned',
              value: _fmt(code.lastScannedAt),
              isLast: true,
            ),
        ]),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Location section
  // ---------------------------------------------------------------------------
  bool _hasLocation(QrCodeModel code) =>
      code.firstScannedPlace != null ||
      code.lastScannedPlace != null ||
      code.firstScannedLat != null;

  Widget _buildLocationSection(QrCodeModel code) {
    String coords(double? lat, double? lng) {
      if (lat == null || lng == null) return '';
      return '${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)}';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader('LOCATION'),
        _InfoCard(children: [
          if (code.firstScannedPlace != null || code.firstScannedLat != null)
            _InfoRow(
              label: 'First scanned',
              value: [
                if (code.firstScannedPlace != null) code.firstScannedPlace!,
                if (code.firstScannedLat != null)
                  coords(code.firstScannedLat, code.firstScannedLng),
              ].join('\n'),
            ),
          if (code.lastScannedPlace != null || code.lastScannedLat != null)
            _InfoRow(
              label: 'Last scanned',
              value: [
                if (code.lastScannedPlace != null) code.lastScannedPlace!,
                if (code.lastScannedLat != null)
                  coords(code.lastScannedLat, code.lastScannedLng),
              ].join('\n'),
              isLast: true,
            ),
        ]),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Reusable section header
// ---------------------------------------------------------------------------
class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: AppTheme.textSecondary,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Card that groups info rows with dividers
// ---------------------------------------------------------------------------
class _InfoCard extends StatelessWidget {
  final List<Widget> children;
  const _InfoCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          for (int i = 0; i < children.length; i++) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: children[i],
            ),
            if (i < children.length - 1)
              Divider(height: 1, color: Theme.of(context).colorScheme.outlineVariant),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Label + value row inside an info card
// ---------------------------------------------------------------------------
class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final Widget? trailing;
  final bool isLast;

  const _InfoRow({
    required this.label,
    required this.value,
    this.trailing,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 8),
            trailing!,
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tappable action tile (URL / email / text)
// ---------------------------------------------------------------------------
class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String text;
  final String? actionLabel;
  final VoidCallback? onTap;
  final VoidCallback onCopy;

  const _ActionTile({
    required this.icon,
    required this.text,
    this.actionLabel,
    this.onTap,
    required this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: onTap != null
              ? AppTheme.primary.withValues(alpha: 0.05)
              : Theme.of(context).colorScheme.surfaceContainerLow,
          border: Border.all(
            color: onTap != null
                ? AppTheme.primary.withValues(alpha: 0.25)
                : Theme.of(context).colorScheme.outlineVariant,
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: onTap != null ? AppTheme.primary : AppTheme.textSecondary,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                text,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: onTap != null
                      ? AppTheme.primary
                      : Theme.of(context).colorScheme.onSurface,
                  fontWeight: FontWeight.w500,
                  decoration:
                      onTap != null ? TextDecoration.underline : null,
                  decorationColor: AppTheme.primary,
                ),
              ),
            ),
            const SizedBox(width: 8),
            if (onTap != null)
              Icon(Icons.arrow_outward_rounded,
                  size: 16,
                  color: AppTheme.primary.withValues(alpha: 0.7))
            else
              GestureDetector(
                onTap: onCopy,
                child: const Icon(Icons.copy_rounded,
                    size: 18, color: AppTheme.textSecondary),
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Contact row (phone / email line)
// ---------------------------------------------------------------------------
class _ContactRow extends StatelessWidget {
  final IconData icon;
  final String value;
  final VoidCallback onCopy;

  const _ContactRow({
    required this.icon,
    required this.value,
    required this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppTheme.textSecondary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(color: AppTheme.textSecondary),
          ),
        ),
        GestureDetector(
          onTap: onCopy,
          child: const Icon(Icons.copy_rounded,
              size: 18, color: AppTheme.textSecondary),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Colour selector circle
// ---------------------------------------------------------------------------
class _ColourCircle extends StatelessWidget {
  final Color color;
  final bool isSelected;
  final VoidCallback onTap;

  const _ColourCircle({
    required this.color,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: isSelected ? AppTheme.primary : Theme.of(context).colorScheme.outlineVariant,
            width: isSelected ? 2.5 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppTheme.primary.withValues(alpha: 0.35),
                    blurRadius: 6,
                  )
                ]
              : null,
        ),
      ),
    );
  }
}
