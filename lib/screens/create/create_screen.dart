import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../core/theme/app_theme.dart';
import '../../data/models/qr_code_model.dart';
import '../../providers/qr_code_providers.dart';

// ---------------------------------------------------------------------------
// Top-level helpers — accessed by both state and sub-widgets
// ---------------------------------------------------------------------------
String _typeLabel(QrCodeType type) => switch (type) {
      QrCodeType.url => 'URL',
      QrCodeType.text => 'Text',
      QrCodeType.wifi => 'WiFi',
      QrCodeType.contact => 'Contact',
      QrCodeType.email => 'Email',
    };

String _typeDescription(QrCodeType type) => switch (type) {
      QrCodeType.url => 'Website link or any URL',
      QrCodeType.text => 'Plain text or a note',
      QrCodeType.wifi => 'Share network credentials',
      QrCodeType.contact => 'Name, phone, and email',
      QrCodeType.email => 'Pre-filled email address',
    };

IconData _typeIcon(QrCodeType type) => switch (type) {
      QrCodeType.url => Icons.link_rounded,
      QrCodeType.text => Icons.text_fields_rounded,
      QrCodeType.wifi => Icons.wifi_rounded,
      QrCodeType.contact => Icons.person_rounded,
      QrCodeType.email => Icons.email_rounded,
    };

// ---------------------------------------------------------------------------
// Social & payment templates
// ---------------------------------------------------------------------------
class _SocialTemplate {
  final String label;
  final String hint;     // shown in the text field
  final String prefix;   // prepended to the user's handle to form a URL
  final IconData icon;
  final Color color;

  const _SocialTemplate({
    required this.label,
    required this.hint,
    required this.prefix,
    required this.icon,
    required this.color,
  });

  String buildUrl(String handle) {
    final clean = handle.replaceFirst(RegExp(r'^@'), '');
    return '$prefix$clean';
  }
}

const _socialTemplates = [
  _SocialTemplate(
    label: 'Instagram',
    hint: '@yourhandle',
    prefix: 'https://instagram.com/',
    icon: Icons.camera_alt_outlined,
    color: Color(0xFFE1306C),
  ),
  _SocialTemplate(
    label: 'X / Twitter',
    hint: '@yourhandle',
    prefix: 'https://x.com/',
    icon: Icons.alternate_email_rounded,
    color: Color(0xFF000000),
  ),
  _SocialTemplate(
    label: 'TikTok',
    hint: '@yourhandle',
    prefix: 'https://tiktok.com/@',
    icon: Icons.music_note_rounded,
    color: Color(0xFF010101),
  ),
  _SocialTemplate(
    label: 'LinkedIn',
    hint: 'your-name',
    prefix: 'https://linkedin.com/in/',
    icon: Icons.work_outline_rounded,
    color: Color(0xFF0A66C2),
  ),
  _SocialTemplate(
    label: 'Venmo',
    hint: '@yourhandle',
    prefix: 'https://venmo.com/',
    icon: Icons.attach_money_rounded,
    color: Color(0xFF3D95CE),
  ),
  _SocialTemplate(
    label: 'PayPal',
    hint: 'your-name',
    prefix: 'https://paypal.me/',
    icon: Icons.payment_rounded,
    color: Color(0xFF003087),
  ),
  _SocialTemplate(
    label: 'YouTube',
    hint: '@yourchannel',
    prefix: 'https://youtube.com/@',
    icon: Icons.play_circle_outline_rounded,
    color: Color(0xFFFF0000),
  ),
  _SocialTemplate(
    label: 'Snapchat',
    hint: 'yourhandle',
    prefix: 'https://snapchat.com/add/',
    icon: Icons.wb_sunny_outlined,
    color: Color(0xFFFFFC00),
  ),
];

// ---------------------------------------------------------------------------
// Colour presets
// ---------------------------------------------------------------------------
const _fgPresets = [
  Color(0xFF000000), // Black
  Color(0xFF4F46E5), // Indigo
  Color(0xFF0F766E), // Teal
  Color(0xFF1D4ED8), // Blue
  Color(0xFF7C3AED), // Purple
  Color(0xFFB45309), // Amber
];

const _bgPresets = [
  Color(0xFFFFFFFF), // White
  Color(0xFFF9FAFB), // Off-white
  Color(0xFFEEF2FF), // Light indigo
  Color(0xFFF0FDF4), // Light green
  Color(0xFFFFF7ED), // Light orange
  Color(0xFFF0F9FF), // Light blue
];

// ---------------------------------------------------------------------------
// Create Screen
// ---------------------------------------------------------------------------
class CreateScreen extends ConsumerStatefulWidget {
  const CreateScreen({super.key});

  @override
  ConsumerState<CreateScreen> createState() => _CreateScreenState();
}

class _CreateScreenState extends ConsumerState<CreateScreen> {
  // Navigation
  int _step = 0;
  QrCodeType _type = QrCodeType.url;

  // Social template (set when user picks a template; null for standard types)
  _SocialTemplate? _socialTemplate;

  // Common
  final _labelCtrl = TextEditingController();

  // URL / social handle
  final _urlCtrl = TextEditingController();

  // Text
  final _textCtrl = TextEditingController();

  // WiFi
  final _ssidCtrl = TextEditingController();
  final _wifiPassCtrl = TextEditingController();
  String _wifiSecurity = 'WPA';
  bool _wifiPassVisible = false;

  // Contact
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _contactEmailCtrl = TextEditingController();

  // Email
  final _emailToCtrl = TextEditingController();
  final _emailSubjectCtrl = TextEditingController();
  final _emailBodyCtrl = TextEditingController();

  // Colours
  Color _fgColor = const Color(0xFF000000);
  Color _bgColor = const Color(0xFFFFFFFF);

  bool _saving = false;

  @override
  void dispose() {
    for (final c in [
      _labelCtrl, _urlCtrl, _textCtrl, _ssidCtrl, _wifiPassCtrl,
      _nameCtrl, _phoneCtrl, _contactEmailCtrl,
      _emailToCtrl, _emailSubjectCtrl, _emailBodyCtrl,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Content + validation
  // ---------------------------------------------------------------------------
  String _buildContent() {
    return switch (_type) {
      QrCodeType.url => () {
          final raw = _urlCtrl.text.trim();
          if (raw.isEmpty) return '';
          if (_socialTemplate != null) return _socialTemplate!.buildUrl(raw);
          return raw.startsWith('http') ? raw : 'https://$raw';
        }(),
      QrCodeType.text => _textCtrl.text.trim(),
      QrCodeType.wifi =>
        'WIFI:T:$_wifiSecurity;S:${_ssidCtrl.text};P:${_wifiPassCtrl.text};;',
      QrCodeType.contact =>
        'BEGIN:VCARD\nVERSION:3.0\nFN:${_nameCtrl.text}\n'
            'TEL:${_phoneCtrl.text}\nEMAIL:${_contactEmailCtrl.text}\nEND:VCARD',
      QrCodeType.email => () {
          final s = Uri.encodeComponent(_emailSubjectCtrl.text.trim());
          final b = Uri.encodeComponent(_emailBodyCtrl.text.trim());
          return 'mailto:${_emailToCtrl.text.trim()}?subject=$s&body=$b';
        }(),
    };
  }

  bool _isValid() => switch (_type) {
        QrCodeType.url => _urlCtrl.text.trim().isNotEmpty,
        QrCodeType.text => _textCtrl.text.trim().isNotEmpty,
        QrCodeType.wifi => _ssidCtrl.text.trim().isNotEmpty,
        QrCodeType.contact => _nameCtrl.text.trim().isNotEmpty,
        QrCodeType.email => _emailToCtrl.text.trim().isNotEmpty,
      };

  String _autoLabel() => switch (_type) {
        QrCodeType.url => () {
            if (_socialTemplate != null) {
              final handle = _urlCtrl.text.trim();
              return '${_socialTemplate!.label} · ${handle.startsWith('@') ? handle : '@$handle'}';
            }
            try {
              return Uri.parse(_urlCtrl.text.trim())
                  .host
                  .replaceAll('www.', '');
            } catch (_) {
              return _urlCtrl.text.trim();
            }
          }(),
        QrCodeType.text => () {
            final t = _textCtrl.text.trim();
            return t.length > 30 ? '${t.substring(0, 30)}…' : t;
          }(),
        QrCodeType.wifi => _ssidCtrl.text.trim(),
        QrCodeType.contact => _nameCtrl.text.trim(),
        QrCodeType.email => _emailToCtrl.text.trim(),
      };

  String _labelHint() => switch (_type) {
        QrCodeType.url => 'e.g. Google',
        QrCodeType.text => 'e.g. Meeting notes',
        QrCodeType.wifi => 'e.g. Home WiFi',
        QrCodeType.contact => 'e.g. John Doe',
        QrCodeType.email => 'e.g. Support email',
      };

  String _colorToHex(Color c) {
    final hex = c.toARGB32().toRadixString(16).padLeft(8, '0');
    return '#${hex.substring(2).toUpperCase()}';
  }

  // ---------------------------------------------------------------------------
  // Save
  // ---------------------------------------------------------------------------
  Future<void> _save() async {
    if (!_isValid()) return;
    setState(() => _saving = true);

    try {
      final user = Supabase.instance.client.auth.currentUser!;
      final content = _buildContent();
      final rawLabel = _labelCtrl.text.trim();
      final label =
          rawLabel.isNotEmpty ? rawLabel : (_autoLabel().isEmpty ? _typeLabel(_type) : _autoLabel());

      final qrCode = QrCodeModel(
        id: const Uuid().v4(),
        userId: user.id,
        label: label,
        type: _type,
        content: content,
        source: QrCodeSource.created,
        foregroundColor: _colorToHex(_fgColor),
        backgroundColor: _colorToHex(_bgColor),
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
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: _step == 0
            ? CloseButton(onPressed: () => context.pop())
            : BackButton(onPressed: () => setState(() => _step = 0)),
        title: Text(_step == 0 ? 'New QR Code' : '${_typeLabel(_type)} code'),
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        child: _step == 0
            ? _TypePicker(
                key: const ValueKey(0),
                onSelect: (t) {
                  setState(() {
                    _type = t;
                    _socialTemplate = null;
                    _urlCtrl.clear();
                    _step = 1;
                  });
                },
                onSelectSocial: (template) {
                  setState(() {
                    _type = QrCodeType.url;
                    _socialTemplate = template;
                    _urlCtrl.clear();
                    _step = 1;
                  });
                },
              )
            : _buildConfigureStep(),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Step 1 — configure + preview
  // ---------------------------------------------------------------------------
  Widget _buildConfigureStep() {
    final content = _buildContent();
    final valid = _isValid();

    return SingleChildScrollView(
      key: const ValueKey(1),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 48),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Label ──────────────────────────────────────────────────────────
          const SizedBox(height: 12),
          TextField(
            controller: _labelCtrl,
            onChanged: (_) => setState(() {}),
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: 'Label (optional)',
              hintText: _labelHint(),
            ),
          ),

          const SizedBox(height: 16),

          // ── Type-specific fields ───────────────────────────────────────────
          ..._buildTypeFields(),

          const SizedBox(height: 32),

          // ── Live QR preview ────────────────────────────────────────────────
          Center(
            child: Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                color: valid ? _bgColor : Theme.of(context).colorScheme.surfaceContainerLow,
                border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: valid
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: QrImageView(
                        data: content,
                        version: QrVersions.auto,
                        size: 200,
                        backgroundColor: _bgColor,
                        eyeStyle: QrEyeStyle(
                          eyeShape: QrEyeShape.square,
                          color: _fgColor,
                        ),
                        dataModuleStyle: QrDataModuleStyle(
                          dataModuleShape: QrDataModuleShape.square,
                          color: _fgColor,
                        ),
                      ),
                    )
                  : const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.qr_code_rounded,
                          size: 64,
                          color: AppTheme.border,
                        ),
                        SizedBox(height: 8),
                        Text(
                          'Preview',
                          style: TextStyle(color: AppTheme.textSecondary),
                        ),
                      ],
                    ),
            ),
          ),

          const SizedBox(height: 32),

          // ── Colour pickers ─────────────────────────────────────────────────
          Text('Colours', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 14),

          Row(
            children: [
              SizedBox(
                width: 90,
                child: Text(
                  'QR code',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              ..._fgPresets.map(
                (c) => _ColourCircle(
                  color: c,
                  isSelected: _fgColor == c,
                  onTap: () => setState(() => _fgColor = c),
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          Row(
            children: [
              SizedBox(
                width: 90,
                child: Text(
                  'Background',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              ..._bgPresets.map(
                (c) => _ColourCircle(
                  color: c,
                  isSelected: _bgColor == c,
                  onTap: () => setState(() => _bgColor = c),
                ),
              ),
            ],
          ),

          const SizedBox(height: 36),

          // ── Save button ────────────────────────────────────────────────────
          FilledButton(
            onPressed: (valid && !_saving) ? _save : null,
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
        ],
      ),
    );
  }

  List<Widget> _buildTypeFields() {
    void rebuild(_) => setState(() {});

    return switch (_type) {
      // ── URL / Social template ───────────────────────────────────────────────
      QrCodeType.url => [
          if (_socialTemplate != null) ...[
            // Show which template is active and let the user swap it
            GestureDetector(
              onTap: () => setState(() {
                _socialTemplate = null;
                _urlCtrl.clear();
              }),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: _socialTemplate!.color.withValues(alpha: 0.08),
                  border: Border.all(
                      color: _socialTemplate!.color.withValues(alpha: 0.3)),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(_socialTemplate!.icon,
                        color: _socialTemplate!.color, size: 20),
                    const SizedBox(width: 10),
                    Text(
                      _socialTemplate!.label,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: _socialTemplate!.color,
                      ),
                    ),
                    const Spacer(),
                    Icon(Icons.close_rounded,
                        size: 16, color: _socialTemplate!.color),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _urlCtrl,
              onChanged: rebuild,
              autocorrect: false,
              decoration: InputDecoration(
                labelText: '${_socialTemplate!.label} handle *',
                hintText: _socialTemplate!.hint,
                prefixIcon: const Icon(Icons.alternate_email_rounded),
              ),
            ),
          ] else
            TextField(
              controller: _urlCtrl,
              onChanged: rebuild,
              keyboardType: TextInputType.url,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'URL *',
                hintText: 'https://example.com',
                prefixIcon: Icon(Icons.link_rounded),
              ),
            ),
        ],

      // ── Text ───────────────────────────────────────────────────────────────
      QrCodeType.text => [
          TextField(
            controller: _textCtrl,
            onChanged: rebuild,
            maxLines: 5,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Text *',
              hintText: 'Enter any text…',
              alignLabelWithHint: true,
            ),
          ),
        ],

      // ── WiFi ───────────────────────────────────────────────────────────────
      QrCodeType.wifi => [
          TextField(
            controller: _ssidCtrl,
            onChanged: rebuild,
            decoration: const InputDecoration(
              labelText: 'Network name (SSID) *',
              prefixIcon: Icon(Icons.wifi_rounded),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _wifiPassCtrl,
            onChanged: rebuild,
            obscureText: !_wifiPassVisible,
            decoration: InputDecoration(
              labelText: 'Password',
              prefixIcon: const Icon(Icons.lock_outline_rounded),
              suffixIcon: IconButton(
                icon: Icon(
                  _wifiPassVisible
                      ? Icons.visibility_off_rounded
                      : Icons.visibility_rounded,
                  color: AppTheme.textSecondary,
                ),
                onPressed: () =>
                    setState(() => _wifiPassVisible = !_wifiPassVisible),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text('Security', style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'WPA', label: Text('WPA/WPA2')),
              ButtonSegment(value: 'WEP', label: Text('WEP')),
              ButtonSegment(value: 'nopass', label: Text('None')),
            ],
            selected: {_wifiSecurity},
            onSelectionChanged: (s) =>
                setState(() => _wifiSecurity = s.first),
          ),
        ],

      // ── Contact ────────────────────────────────────────────────────────────
      QrCodeType.contact => [
          TextField(
            controller: _nameCtrl,
            onChanged: rebuild,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Full name *',
              prefixIcon: Icon(Icons.person_outline_rounded),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _phoneCtrl,
            onChanged: rebuild,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              labelText: 'Phone',
              prefixIcon: Icon(Icons.phone_outlined),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _contactEmailCtrl,
            onChanged: rebuild,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'Email',
              prefixIcon: Icon(Icons.email_outlined),
            ),
          ),
        ],

      // ── Email ──────────────────────────────────────────────────────────────
      QrCodeType.email => [
          TextField(
            controller: _emailToCtrl,
            onChanged: rebuild,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'To *',
              hintText: 'recipient@example.com',
              prefixIcon: Icon(Icons.send_outlined),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _emailSubjectCtrl,
            onChanged: rebuild,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Subject',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _emailBodyCtrl,
            onChanged: rebuild,
            maxLines: 3,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Body',
              alignLabelWithHint: true,
            ),
          ),
        ],
    };
  }
}

// ---------------------------------------------------------------------------
// Step 0 — Type picker
// ---------------------------------------------------------------------------
class _TypePicker extends StatelessWidget {
  final ValueChanged<QrCodeType> onSelect;
  final ValueChanged<_SocialTemplate> onSelectSocial;

  const _TypePicker({
    super.key,
    required this.onSelect,
    required this.onSelectSocial,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 48),
      children: [
        Text(
          'Choose a type',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 4),
        Text(
          'Select the kind of QR code you want to create.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 24),
        ...QrCodeType.values.map(
          (t) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _TypeOptionCard(type: t, onTap: () => onSelect(t)),
          ),
        ),
        const SizedBox(height: 8),
        Text('Social & Payments',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
          'Create a shareable link for your profiles and payment apps.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 16),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 2.4,
          children: _socialTemplates
              .map((t) => _SocialTemplateCard(
                    template: t,
                    onTap: () => onSelectSocial(t),
                  ))
              .toList(),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Type option card
// ---------------------------------------------------------------------------
class _TypeOptionCard extends StatelessWidget {
  final QrCodeType type;
  final VoidCallback onTap;

  const _TypeOptionCard({required this.type, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          border: Border.all(
              color: Theme.of(context).colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(_typeIcon(type), color: AppTheme.primary),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _typeLabel(type),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(
                    _typeDescription(type),
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: AppTheme.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Social template card — compact 2-column grid tile
// ---------------------------------------------------------------------------
class _SocialTemplateCard extends StatelessWidget {
  final _SocialTemplate template;
  final VoidCallback onTap;

  const _SocialTemplateCard({required this.template, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: template.color.withValues(alpha: 0.07),
          border:
              Border.all(color: template.color.withValues(alpha: 0.25)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(template.icon, color: template.color, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                template.label,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
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
        width: 30,
        height: 30,
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
                  ),
                ]
              : null,
        ),
      ),
    );
  }
}
