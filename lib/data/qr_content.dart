import 'models/qr_code_model.dart';
import 'qr_payload.dart';

QrCodeType detectQrType(String content) {
  if (content.startsWith('WIFI:')) return QrCodeType.wifi;
  if (content.startsWith('BEGIN:VCARD')) return QrCodeType.contact;
  if (content.startsWith('mailto:')) return QrCodeType.email;
  final asUrl = normalizeHttpUrl(content);
  if (asUrl.startsWith('http://') || asUrl.startsWith('https://')) {
    return QrCodeType.url;
  }
  return QrCodeType.text;
}

bool isFidoContent(String content) =>
    content.toUpperCase().startsWith('FIDO:');

bool isLaunchableQr(QrCodeType type) =>
    type == QrCodeType.url || type == QrCodeType.email;

String autoQrLabel(String content, QrCodeType type) {
  return switch (type) {
    QrCodeType.url =>
      Uri.tryParse(normalizeHttpUrl(content))?.host.replaceAll('www.', '') ??
          content,
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
