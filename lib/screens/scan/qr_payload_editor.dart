import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../data/qr_payload.dart';

class PayloadFlagToggles extends StatelessWidget {
  final bool hasDate;
  final bool hasParts;
  final ValueChanged<bool> onHasDate;
  final ValueChanged<bool> onHasParts;

  const PayloadFlagToggles({
    super.key,
    required this.hasDate,
    required this.hasParts,
    required this.onHasDate,
    required this.onHasParts,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Has a date'),
          subtitle: const Text('Open with today’s date, or pick another'),
          value: hasDate,
          onChanged: onHasDate,
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Has editable parts'),
          subtitle: const Text('Show pickers for numbers and other values'),
          value: hasParts,
          onChanged: onHasParts,
        ),
      ],
    );
  }
}

class QrPayloadEditor extends StatefulWidget {
  final String content;
  final bool hasDate;
  final bool hasParts;
  final ValueChanged<String> onContentChanged;

  const QrPayloadEditor({
    super.key,
    required this.content,
    required this.hasDate,
    required this.hasParts,
    required this.onContentChanged,
  });

  @override
  State<QrPayloadEditor> createState() => _QrPayloadEditorState();
}

class _QrPayloadEditorState extends State<QrPayloadEditor> {
  late QrPayloadBlueprint _blueprint;
  late Map<String, String> _values;

  @override
  void initState() {
    super.initState();
    _rebuild(notify: true);
  }

  @override
  void didUpdateWidget(QrPayloadEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.hasDate != widget.hasDate ||
        oldWidget.hasParts != widget.hasParts) {
      _rebuild(notify: true);
    }
  }

  void _rebuild({required bool notify}) {
    _blueprint = QrPayloadBlueprint.parse(widget.content);
    _values = _blueprint.defaultValues(useTodayForDates: widget.hasDate);
    if (notify) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onContentChanged(_blueprint.assemble(_values));
      });
    }
  }

  List<PayloadPart> get _visibleParts {
    if (widget.hasParts) return _blueprint.parts;
    if (widget.hasDate) {
      return _blueprint.parts
          .where((p) => p.kind == PayloadPartKind.date)
          .toList();
    }
    return const [];
  }

  void _setValue(String id, String value) {
    setState(() => _values[id] = value);
    widget.onContentChanged(_blueprint.assemble(_values));
  }

  Future<void> _pickDate(PayloadPart part) async {
    final pattern = part.datePattern ?? 'yyyy-MM-dd';
    DateTime initial;
    try {
      initial = DateFormat(pattern).parseStrict(_values[part.id] ?? part.original);
    } catch (_) {
      initial = DateTime.now();
    }
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    _setValue(part.id, DateFormat(pattern).format(picked));
  }

  @override
  Widget build(BuildContext context) {
    final parts = _visibleParts;
    if (parts.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Customize', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(
          widget.hasDate
              ? 'Date fields default to today. Change them before you open the code.'
              : 'Edit the values in this code before you open it.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 12),
        ...parts.map(_fieldFor),
      ],
    );
  }

  Widget _fieldFor(PayloadPart part) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: switch (part.kind) {
        PayloadPartKind.date => _DateField(
            label: part.label,
            value: _values[part.id] ?? part.original,
            onTap: () => _pickDate(part),
          ),
        PayloadPartKind.number => _NumberField(
            label: part.label,
            value: _values[part.id] ?? part.original,
            onChanged: (v) => _setValue(part.id, v),
          ),
        PayloadPartKind.text => TextFormField(
            initialValue: _values[part.id] ?? part.original,
            decoration: InputDecoration(labelText: part.label),
            onChanged: (v) => _setValue(part.id, v),
          ),
      },
    );
  }
}

class _DateField extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback onTap;

  const _DateField({
    required this.label,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          suffixIcon: const Icon(Icons.calendar_today_outlined, size: 18),
        ),
        child: Text(value, style: Theme.of(context).textTheme.bodyLarge),
      ),
    );
  }
}

class _NumberField extends StatelessWidget {
  final String label;
  final String value;
  final ValueChanged<String> onChanged;

  const _NumberField({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  int get _n => int.tryParse(value) ?? 0;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextFormField(
            key: ValueKey('$label-$value'),
            initialValue: value,
            decoration: InputDecoration(labelText: label),
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onChanged: onChanged,
          ),
        ),
        IconButton(
          onPressed: () => onChanged('${(_n - 1).clamp(0, 999999)}'),
          icon: const Icon(Icons.remove_circle_outline),
          color: AppTheme.primary,
        ),
        IconButton(
          onPressed: () => onChanged('${(_n + 1).clamp(0, 999999)}'),
          icon: const Icon(Icons.add_circle_outline),
          color: AppTheme.primary,
        ),
      ],
    );
  }
}
