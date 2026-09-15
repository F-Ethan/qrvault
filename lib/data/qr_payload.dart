import 'package:intl/intl.dart';

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

class QrPayloadBlueprint {
  final String original;
  final bool isHttpUrl;
  final List<PayloadPart> parts;

  const QrPayloadBlueprint({
    required this.original,
    required this.isHttpUrl,
    required this.parts,
  });

  bool get hasDateParts => parts.any((p) => p.kind == PayloadPartKind.date);
  bool get hasEditableParts => parts.isNotEmpty;

  static final _dateFormats = <DateFormat>[
    DateFormat('yyyy-MM-dd'),
    DateFormat('yyyy/MM/dd'),
    DateFormat('MM/dd/yyyy'),
    DateFormat('M/d/yyyy'),
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
    final uri = Uri.tryParse(trimmed);
    if (uri == null ||
        !(uri.isScheme('http') || uri.isScheme('https')) ||
        uri.host.isEmpty) {
      return QrPayloadBlueprint(
        original: trimmed,
        isHttpUrl: false,
        parts: const [],
      );
    }

    final parts = <PayloadPart>[];
    var i = 0;
    for (final segment in uri.pathSegments) {
      final kind = _classify(segment, isQuery: false);
      if (kind != null) {
        parts.add(
          PayloadPart(
            id: 'path_$i',
            kind: kind,
            label: _labelFor(kind, 'Path $i'),
            original: segment,
            pathIndex: i,
            datePattern: kind == PayloadPartKind.date
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
      if (kind == null) return;
      parts.add(
        PayloadPart(
          id: 'q_$key',
          kind: kind,
          label: _labelFor(kind, key),
          original: value,
          queryKey: key,
          datePattern:
              kind == PayloadPartKind.date ? _patternFor(value) : null,
        ),
      );
    });

    return QrPayloadBlueprint(
      original: trimmed,
      isHttpUrl: true,
      parts: parts,
    );
  }

  static String _labelFor(PayloadPartKind kind, String fallback) {
    return switch (kind) {
      PayloadPartKind.date => fallback.toLowerCase() == 'd' ||
              fallback.toLowerCase() == 'date'
          ? 'Date'
          : fallback,
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
        format.parseStrict(raw);
        return format.pattern;
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
}

String? datePayloadTemplate(String content) {
  final parsed = QrPayloadBlueprint.parse(content);
  if (!parsed.hasDateParts) return null;
  return parsed.dateTemplate();
}
