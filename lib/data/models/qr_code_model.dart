enum QrCodeType { url, text, wifi, contact, email }

enum QrCodeSource { scanned, created }

class QrCodeModel {
  final String id;
  final String userId;
  final String label;
  final QrCodeType type;
  final String content;
  final QrCodeSource source;
  final String foregroundColor;
  final String backgroundColor;
  final int scanCount;
  final DateTime? firstScannedAt;
  final DateTime? lastScannedAt;
  final double? firstScannedLat;
  final double? firstScannedLng;
  final String? firstScannedPlace;
  final double? lastScannedLat;
  final double? lastScannedLng;
  final String? lastScannedPlace;
  final DateTime createdAt;
  final DateTime updatedAt;

  const QrCodeModel({
    required this.id,
    required this.userId,
    required this.label,
    required this.type,
    required this.content,
    required this.source,
    this.foregroundColor = '#000000',
    this.backgroundColor = '#FFFFFF',
    this.scanCount = 0,
    this.firstScannedAt,
    this.lastScannedAt,
    this.firstScannedLat,
    this.firstScannedLng,
    this.firstScannedPlace,
    this.lastScannedLat,
    this.lastScannedLng,
    this.lastScannedPlace,
    required this.createdAt,
    required this.updatedAt,
  });

  // -- Deserialise from Supabase JSON response --
  factory QrCodeModel.fromJson(Map<String, dynamic> json) => QrCodeModel(
        id: json['id'] as String,
        userId: json['user_id'] as String,
        label: json['label'] as String,
        type: QrCodeType.values.firstWhere(
          (e) => e.name == json['type'],
          orElse: () => QrCodeType.text,
        ),
        content: json['content'] as String,
        source: QrCodeSource.values.firstWhere(
          (e) => e.name == json['source'],
          orElse: () => QrCodeSource.created,
        ),
        foregroundColor:
            json['foreground_color'] as String? ?? '#000000',
        backgroundColor:
            json['background_color'] as String? ?? '#FFFFFF',
        scanCount: json['scan_count'] as int? ?? 0,
        firstScannedAt: json['first_scanned_at'] != null
            ? DateTime.parse(json['first_scanned_at'] as String)
            : null,
        lastScannedAt: json['last_scanned_at'] != null
            ? DateTime.parse(json['last_scanned_at'] as String)
            : null,
        firstScannedLat: (json['first_scanned_lat'] as num?)?.toDouble(),
        firstScannedLng: (json['first_scanned_lng'] as num?)?.toDouble(),
        firstScannedPlace: json['first_scanned_place'] as String?,
        lastScannedLat: (json['last_scanned_lat'] as num?)?.toDouble(),
        lastScannedLng: (json['last_scanned_lng'] as num?)?.toDouble(),
        lastScannedPlace: json['last_scanned_place'] as String?,
        createdAt: DateTime.parse(json['created_at'] as String),
        updatedAt: DateTime.parse(json['updated_at'] as String),
      );

  // -- Serialise for sending to Supabase --
  Map<String, dynamic> toJson() => {
        'id': id,
        'user_id': userId,
        'label': label,
        'type': type.name,
        'content': content,
        'source': source.name,
        'foreground_color': foregroundColor,
        'background_color': backgroundColor,
        'scan_count': scanCount,
        'first_scanned_at': firstScannedAt?.toIso8601String(),
        'last_scanned_at': lastScannedAt?.toIso8601String(),
        'first_scanned_lat': firstScannedLat,
        'first_scanned_lng': firstScannedLng,
        'first_scanned_place': firstScannedPlace,
        'last_scanned_lat': lastScannedLat,
        'last_scanned_lng': lastScannedLng,
        'last_scanned_place': lastScannedPlace,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  // -- Convenience copy with overrides --
  QrCodeModel copyWith({
    String? id,
    String? userId,
    String? label,
    QrCodeType? type,
    String? content,
    QrCodeSource? source,
    String? foregroundColor,
    String? backgroundColor,
    int? scanCount,
    DateTime? firstScannedAt,
    DateTime? lastScannedAt,
    double? firstScannedLat,
    double? firstScannedLng,
    String? firstScannedPlace,
    double? lastScannedLat,
    double? lastScannedLng,
    String? lastScannedPlace,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) =>
      QrCodeModel(
        id: id ?? this.id,
        userId: userId ?? this.userId,
        label: label ?? this.label,
        type: type ?? this.type,
        content: content ?? this.content,
        source: source ?? this.source,
        foregroundColor: foregroundColor ?? this.foregroundColor,
        backgroundColor: backgroundColor ?? this.backgroundColor,
        scanCount: scanCount ?? this.scanCount,
        firstScannedAt: firstScannedAt ?? this.firstScannedAt,
        lastScannedAt: lastScannedAt ?? this.lastScannedAt,
        firstScannedLat: firstScannedLat ?? this.firstScannedLat,
        firstScannedLng: firstScannedLng ?? this.firstScannedLng,
        firstScannedPlace: firstScannedPlace ?? this.firstScannedPlace,
        lastScannedLat: lastScannedLat ?? this.lastScannedLat,
        lastScannedLng: lastScannedLng ?? this.lastScannedLng,
        lastScannedPlace: lastScannedPlace ?? this.lastScannedPlace,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
}
