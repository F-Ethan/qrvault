import 'package:flutter_test/flutter_test.dart';
import 'package:qrvault/data/qr_payload.dart';

void main() {
  test('detects date query and defaults it to today', () {
    const raw = 'https://daycare.example/checkin?d=20240115';
    final parsed = QrPayloadBlueprint.parse(raw);
    expect(parsed.hasDateParts, isTrue);
    final values = parsed.defaultValues(useTodayForDates: true);
    final assembled = parsed.assemble(values);
    expect(assembled.contains('20240115'), isFalse);
    expect(Uri.parse(assembled).queryParameters['d']?.length, 8);
  });

  test('builds a date template for matching', () {
    const a = 'https://x.example/in/2026-09-13';
    const b = 'https://x.example/in/2026-09-14';
    expect(
      QrPayloadBlueprint.parse(a).dateTemplate(),
      QrPayloadBlueprint.parse(b).dateTemplate(),
    );
  });

  test('number path segments are editable', () {
    final parsed =
        QrPayloadBlueprint.parse('https://example.com/room/12/sign');
    expect(parsed.parts.any((p) => p.kind == PayloadPartKind.number), isTrue);
  });

  test('skips tokens and keeps short query text', () {
    final parsed = QrPayloadBlueprint.parse(
      'https://example.com/login?token=abc123secret&room=Maple',
    );
    expect(parsed.parts.any((p) => p.queryKey == 'token'), isFalse);
    expect(
      parsed.parts.any((p) => p.queryKey == 'room' && p.kind == PayloadPartKind.text),
      isTrue,
    );
  });

  test('detects US short dates in the path', () {
    const raw = 'https://www.campmarshal.com/10-20-24/more-info-here';
    final parsed = QrPayloadBlueprint.parse(raw);
    expect(parsed.hasDateParts, isTrue);
    final date = parsed.parts.singleWhere((p) => p.kind == PayloadPartKind.date);
    expect(date.original, '10-20-24');
    expect(date.datePattern, 'MM-dd-yy');
    final assembled = parsed.assemble(
      parsed.defaultValues(useTodayForDates: true),
    );
    expect(assembled.contains('10-20-24'), isFalse);
    expect(assembled.contains('more-info-here'), isTrue);
  });

  test('detects ISO dates even when the scheme is mistyped', () {
    const raw =
        'https//:www.campmarshal.com/2024-10-24/this_is_the_way';
    expect(normalizeHttpUrl(raw).startsWith('https://'), isTrue);
    final parsed = QrPayloadBlueprint.parse(raw);
    expect(parsed.hasDateParts, isTrue);
    expect(
      parsed.parts.any((p) => p.original == '2024-10-24'),
      isTrue,
    );
  });

  test('lets a path slug be chosen as text', () {
    const raw =
        'https://www.campmarshal.com/2024-10-24/this_is_the_way';
    final parsed = QrPayloadBlueprint.parse(raw);
    expect(
      parsed.slots.any((s) => s.original == 'this_is_the_way'),
      isTrue,
    );
    final slug = parsed.slots.firstWhere((s) => s.original == 'this_is_the_way');
    final configs = upsertPayloadSlot(
      suggestedPayloadConfigs(raw, hasDate: true, hasParts: false),
      slug,
      PayloadPartKind.text,
    );
    final parts = parsed.partsFromConfigs(configs);
    expect(parts.any((p) => p.original == 'this_is_the_way'), isTrue);
    final assembled = parsed.assembleWith(parts, {
      for (final p in parts)
        p.id: p.kind == PayloadPartKind.text ? 'new-slug' : p.original,
    });
    expect(assembled.contains('new-slug'), isTrue);
    expect(assembled.contains('2024-10-24'), isTrue);
  });
}
