import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_theme.dart';
import '../../data/models/qr_code_model.dart';
import '../../data/qr_content.dart';
import '../../data/qr_payload.dart';

Future<void> showMapPinSheet({
  required BuildContext context,
  required List<QrCodeModel> codes,
}) {
  final unique = <String, QrCodeModel>{
    for (final code in codes) code.id: code,
  }.values.toList();
  unique.sort((a, b) => a.displayLabel.compareTo(b.displayLabel));

  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (context) {
      if (unique.length == 1) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _SheetHandle(),
              const SizedBox(height: 24),
              _PinCodeBlock(code: unique.first, dense: false),
            ],
          ),
        );
      }

      final half = MediaQuery.sizeOf(context).height * 0.5;
      return SizedBox(
        height: half,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _SheetHandle(),
              const SizedBox(height: 16),
              Text(
                '${unique.length} codes',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ListView.separated(
                  itemCount: unique.length,
                  separatorBuilder: (_, __) => Divider(
                    height: 1,
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                  itemBuilder: (context, index) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: _PinCodeBlock(code: unique[index], dense: true),
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

class _SheetHandle extends StatelessWidget {
  const _SheetHandle();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 40,
        height: 4,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.outlineVariant,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

class _PinCodeBlock extends StatelessWidget {
  const _PinCodeBlock({required this.code, required this.dense});

  final QrCodeModel code;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final link = _linkLabel(code);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          code.displayLabel,
          style: dense
              ? Theme.of(context).textTheme.titleMedium
              : Theme.of(context).textTheme.titleLarge,
        ),
        if (link != null) ...[
          const SizedBox(height: 8),
          InkWell(
            onTap: () => _openLink(code),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                link,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppTheme.primary,
                      decoration: TextDecoration.underline,
                      decorationColor: AppTheme.primary,
                    ),
              ),
            ),
          ),
        ] else ...[
          const SizedBox(height: 8),
          Text(
            autoQrLabel(code.content, code.type),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
        ],
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: () {
              Navigator.pop(context);
              context.push('/detail/${code.id}');
            },
            child: const Text('Card'),
          ),
        ),
      ],
    );
  }
}

String? _linkLabel(QrCodeModel code) {
  if (isFidoContent(code.content) || !isLaunchableQr(code.type)) return null;
  if (code.type == QrCodeType.email) {
    return code.content.replaceFirst('mailto:', '').split('?').first;
  }
  return normalizeHttpUrl(code.content);
}

Future<void> _openLink(QrCodeModel code) async {
  final label = _linkLabel(code);
  if (label == null) return;
  final raw = code.type == QrCodeType.email
      ? (code.content.startsWith('mailto:') ? code.content : 'mailto:$label')
      : normalizeHttpUrl(code.content);
  final uri = Uri.tryParse(raw);
  if (uri == null) return;
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}
