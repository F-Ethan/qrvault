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
}
