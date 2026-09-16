import 'dart:convert';

import 'package:intl/intl.dart';

/// Fixes common scheme typos (`https//:`, `https:/`) and adds `https://` when missing.
String normalizeHttpUrl(String raw) {
  var value = raw.trim();
  if (value.isEmpty) return value;
  value = value.replaceFirstMapped(
    RegExp(r'^(https?)\/\/:', caseSensitive: false),
    (m) => '${m[1]}://',
  );
  value = value.replaceFirstMapped(
    RegExp(r'^(https?):\/(?!\/)', caseSensitive: false),
    (m) => '${m[1]}://',
  );
  if (!RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*:').hasMatch(value) &&
      value.contains('.')) {
    value = 'https://$value';
  }
  return value;
}

enum PayloadPartKind { date, number, text }

class PayloadPart {
  final String id;
  final PayloadPartKind kind;
  final String label;
  final String original;
  final String? queryKey;
  final int? pathIndex;
  final String? datePattern;

  const PayloadPart({
    required this.id,
    required this.kind,
    required this.label,
    required this.original,
    this.queryKey,
    this.pathIndex,
    this.datePattern,
  });
}

/// One choosable path or query piece. Host / tokens are never included.
class PayloadSlot {
  final String id;
  final String original;
  final int? pathIndex;
  final String? queryKey;
  final PayloadPartKind? suggestedKind;
  final String? suggestedDatePattern;

  const PayloadSlot({
    required this.id,
    required this.original,
    this.pathIndex,
    this.queryKey,
    this.suggestedKind,
    this.suggestedDatePattern,
  });

  String get title => queryKey ?? '/$original';
}

/// User-chosen editable section persisted on the card.
class PayloadPartConfig {
  final String id;
  final PayloadPartKind kind;
  final int? pathIndex;
  final String? queryKey;
  final String? datePattern;

  const PayloadPartConfig({
    required this.id,
    required this.kind,
    this.pathIndex,
    this.queryKey,
    this.datePattern,
  });

  factory PayloadPartConfig.fromJson(Map<String, dynamic> json) {
    final kindName = json['kind'] as String? ?? 'text';
    return PayloadPartConfig(
      id: json['id'] as String,
      kind: PayloadPartKind.values.firstWhere(
        (k) => k.name == kindName,
        orElse: () => PayloadPartKind.text,
      ),
      pathIndex: json['pathIndex'] as int?,
      queryKey: json['queryKey'] as String?,
      datePattern: json['datePattern'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind.name,
        if (pathIndex != null) 'pathIndex': pathIndex,
        if (queryKey != null) 'queryKey': queryKey,
        if (datePattern != null) 'datePattern': datePattern,
      };

  PayloadPart toPart(String original) => PayloadPart(
        id: id,
        kind: kind,
        label: kind == PayloadPartKind.date ? 'Date' : (queryKey ?? original),
        original: original,
        pathIndex: pathIndex,
        queryKey: queryKey,
        datePattern: datePattern,
      );
}

List<PayloadPartConfig> decodePayloadParts(dynamic raw) {
  if (raw == null) return const [];
  final list = raw is String
      ? (raw.isEmpty ? const [] : (jsonDecode(raw) as List))
      : raw is List
          ? raw
          : const [];
  return list
      .whereType<Map>()
      .map((e) => PayloadPartConfig.fromJson(Map<String, dynamic>.from(e)))
      .toList();
}

List<PayloadPartConfig> suggestedPayloadConfigs(
  String content, {
  required bool hasDate,
  required bool hasParts,
}) {
  final parsed = QrPayloadBlueprint.parse(content);
  return [
    for (final slot in parsed.slots)
      if (slot.suggestedKind == PayloadPartKind.date && hasDate)
        PayloadPartConfig(
          id: slot.id,
          kind: PayloadPartKind.date,
          pathIndex: slot.pathIndex,
          queryKey: slot.queryKey,
          datePattern: slot.suggestedDatePattern ?? 'yyyy-MM-dd',
        )
      else if (slot.suggestedKind != null &&
          slot.suggestedKind != PayloadPartKind.date &&
          hasParts)
        PayloadPartConfig(
          id: slot.id,
          kind: slot.suggestedKind!,
          pathIndex: slot.pathIndex,
          queryKey: slot.queryKey,
        ),
  ];
}

List<PayloadPartConfig> addSuggestedPayloadConfigs(
  String content,
  List<PayloadPartConfig> current, {
  required bool dates,
  required bool parts,
}) {
  final extra = suggestedPayloadConfigs(
    content,
    hasDate: dates,
    hasParts: parts,
  );
  final ids = current.map((c) => c.id).toSet();
  return [...current, ...extra.where((c) => !ids.contains(c.id))];
}

List<PayloadPartConfig> upsertPayloadSlot(
  List<PayloadPartConfig> current,
  PayloadSlot slot,
  PayloadPartKind? kind, {
  String? datePattern,
}) {
  final without = current.where((c) => c.id != slot.id).toList();
  if (kind == null) return without;
  final existing = current.where((c) => c.id == slot.id).firstOrNull;
  return [
    ...without,
    PayloadPartConfig(
      id: slot.id,
      kind: kind,
      pathIndex: slot.pathIndex,
      queryKey: slot.queryKey,
      datePattern: kind == PayloadPartKind.date
          ? (datePattern ??
              existing?.datePattern ??
              slot.suggestedDatePattern ??
              'yyyy-MM-dd')
          : null,
    ),
  ];
}

const payloadDatePatterns = [
  'yyyy-MM-dd',
  'MM-dd-yyyy',
  'MM-dd-yy',
  'MM/dd/yyyy',
  'yyyy/MM/dd',
  'yyyyMMdd',
];

class QrPayloadBlueprint {
  final String original;
  final bool isHttpUrl;
  final List<PayloadPart> parts;
  final List<PayloadSlot> slots;

  const QrPayloadBlueprint({
    required this.original,
    required this.isHttpUrl,
    required this.parts,
    this.slots = const [],
  });

  bool get hasDateParts => parts.any((p) => p.kind == PayloadPartKind.date);
  bool get hasEditableParts => parts.isNotEmpty;

  static final _dateFormats = <DateFormat>[
    DateFormat('yyyy-MM-dd'),
    DateFormat('yyyy/MM/dd'),
    DateFormat('MM/dd/yyyy'),
    DateFormat('M/d/yyyy'),
    DateFormat('MM-dd-yyyy'),
    DateFormat('M-d-yyyy'),
    DateFormat('MM/dd/yy'),
    DateFormat('M/d/yy'),
    DateFormat('MM-dd-yy'),
    DateFormat('M-d-yy'),
    DateFormat('yyyyMMdd'),
  ];

  static final _uuid = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );
  static final _longHex = RegExp(r'^[0-9a-fA-F]{16,}$');
  static final _digits = RegExp(r'^\d{1,8}$');
  static final _compactYmd = RegExp(
    r'^(19|20)\d{2}(0[1-9]|1[0-2])(0[1-9]|[12]\d|3[01])$',
  );
  static const _skipPath = {
    'www',
    'api',
    'v1',
    'v2',
    'v3',
    'login',
    'logout',
    'auth',
    'static',
    'assets',
    'public',
    'index',
    'app',
    'http',
    'https',
  };
  static const _skipQuery = {
    'token',
    'sig',
    'signature',
    'hmac',
    'hash',
    'jwt',
    'key',
    'secret',
  };

  factory QrPayloadBlueprint.parse(String content) {
    final trimmed = content.trim();
    final normalized = normalizeHttpUrl(trimmed);
    final uri = Uri.tryParse(normalized);
    if (uri == null ||
        !(uri.isScheme('http') || uri.isScheme('https')) ||
        uri.host.isEmpty) {
      return QrPayloadBlueprint(
        original: trimmed,
        isHttpUrl: false,
        parts: const [],
      );
    }

    final slots = <PayloadSlot>[];
    var i = 0;
    for (final segment in uri.pathSegments) {
      if (segment.isNotEmpty &&
          !_skipPath.contains(segment.toLowerCase())) {
        final kind = _classify(segment, isQuery: false);
        slots.add(
          PayloadSlot(
            id: 'path_$i',
            original: segment,
            pathIndex: i,
            suggestedKind: kind,
            suggestedDatePattern: kind == PayloadPartKind.date
                ? _patternFor(segment)
                : null,
          ),
        );
      }
      i++;
    }

    uri.queryParameters.forEach((key, value) {
      if (_skipQuery.contains(key.toLowerCase())) return;
      final kind = _classify(value, isQuery: true);
      slots.add(
        PayloadSlot(
          id: 'q_$key',
          original: value,
          queryKey: key,
          suggestedKind: kind,
          suggestedDatePattern:
              kind == PayloadPartKind.date ? _patternFor(value) : null,
        ),
      );
    });

    final parts = [
      for (final slot in slots)
        if (slot.suggestedKind != null)
          PayloadPart(
            id: slot.id,
            kind: slot.suggestedKind!,
            label: _labelFor(slot.suggestedKind!, slot.queryKey ?? slot.original),
            original: slot.original,
            pathIndex: slot.pathIndex,
            queryKey: slot.queryKey,
            datePattern: slot.suggestedDatePattern,
          ),
    ];

    return QrPayloadBlueprint(
      original: normalized,
      isHttpUrl: true,
      parts: parts,
      slots: slots,
    );
  }

  static String _labelFor(PayloadPartKind kind, String fallback) {
    return switch (kind) {
      PayloadPartKind.date => 'Date',
      PayloadPartKind.number => fallback,
      PayloadPartKind.text => fallback,
    };
  }

  static PayloadPartKind? _classify(String raw, {required bool isQuery}) {
    final value = raw.trim();
    if (value.isEmpty) return null;
    if (_uuid.hasMatch(value) || _longHex.hasMatch(value)) return null;
    if (value.split('.').length == 3 && value.length > 40) return null;
    if (_patternFor(value) != null) return PayloadPartKind.date;
    if (_digits.hasMatch(value)) return PayloadPartKind.number;
    if (!isQuery && _skipPath.contains(value.toLowerCase())) return null;
    if (!isQuery && value.length < 2) return null;
    if (isQuery && value.length <= 40) return PayloadPartKind.text;
    return null;
  }

  static String? _patternFor(String raw) {
    if (_compactYmd.hasMatch(raw)) return 'yyyyMMdd';
    for (final format in _dateFormats) {
      try {
        final parsed = format.parseStrict(raw);
        if (format.format(parsed) == raw) return format.pattern;
      } catch (_) {}
    }
    return null;
  }

  String dateTemplate() {
    if (!isHttpUrl || !hasDateParts) return original;
    var result = original;
    for (final part in parts.where((p) => p.kind == PayloadPartKind.date)) {
      result = result.replaceFirst(part.original, '{{DATE}}');
    }
    return result;
  }

  Map<String, String> defaultValues({required bool useTodayForDates}) {
    final today = DateTime.now();
    final values = <String, String>{};
    for (final part in parts) {
      if (part.kind == PayloadPartKind.date &&
          useTodayForDates &&
          part.datePattern != null) {
        values[part.id] = DateFormat(part.datePattern).format(today);
      } else {
        values[part.id] = part.original;
      }
    }
    return values;
  }

  String assemble(Map<String, String> values) {
    if (!isHttpUrl) return original;
    final uri = Uri.parse(original);
    final path = [...uri.pathSegments];
    final query = Map<String, String>.from(uri.queryParameters);
    for (final part in parts) {
      final next = values[part.id] ?? part.original;
      if (part.pathIndex != null && part.pathIndex! < path.length) {
        path[part.pathIndex!] = next;
      } else if (part.queryKey != null) {
        query[part.queryKey!] = next;
      }
    }
    return uri.replace(
      pathSegments: path,
      queryParameters: query.isEmpty ? null : query,
    ).toString();
  }

  String assembleWith(
    List<PayloadPart> custom,
    Map<String, String> values,
  ) {
    if (!isHttpUrl) return original;
    final uri = Uri.parse(original);
    final path = [...uri.pathSegments];
    final query = Map<String, String>.from(uri.queryParameters);
    for (final part in custom) {
      final next = values[part.id] ?? part.original;
      if (part.pathIndex != null && part.pathIndex! < path.length) {
        path[part.pathIndex!] = next;
      } else if (part.queryKey != null) {
        query[part.queryKey!] = next;
      }
    }
    return uri.replace(
      pathSegments: path,
      queryParameters: query.isEmpty ? null : query,
    ).toString();
  }

  List<PayloadPart> partsFromConfigs(List<PayloadPartConfig> configs) {
    final byId = {for (final slot in slots) slot.id: slot};
    return [
      for (final config in configs)
        config.toPart(byId[config.id]?.original ?? ''),
    ];
  }
}

String? datePayloadTemplate(
  String content, [
  List<PayloadPartConfig>? configs,
]) {
  final parsed = QrPayloadBlueprint.parse(content);
  final dates = (configs ?? const <PayloadPartConfig>[])
      .where((c) => c.kind == PayloadPartKind.date)
      .toList();
  if (dates.isNotEmpty) {
    var result = parsed.original;
    for (final config in dates) {
      for (final slot in parsed.slots) {
        if (slot.id == config.id) {
          result = result.replaceFirst(slot.original, '{{DATE}}');
          break;
        }
      }
    }
    return result;
  }
  if (!parsed.hasDateParts) return null;
  return parsed.dateTemplate();
}
