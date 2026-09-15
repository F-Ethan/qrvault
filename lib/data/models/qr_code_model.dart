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
  final bool isPinned;
  final bool isPublic;
  final int scanCount;
  final int publicScanCount;
  final int myScanCount;
  final String? customLabel;
  final bool hasMembership;
  final bool hasDate;
  final bool hasParts;
  final String? payloadTemplate;
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
    this.isPinned = false,
    this.isPublic = false,
    this.scanCount = 0,
    this.publicScanCount = 0,
    this.myScanCount = 0,
    this.customLabel,
    this.hasMembership = false,
    this.hasDate = false,
    this.hasParts = false,
    this.payloadTemplate,
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

  String get displayLabel {
    final nick = customLabel?.trim();
    if (nick != null && nick.isNotEmpty) return nick;
    return label;
  }

  double? get mapLat => lastScannedLat ?? firstScannedLat;
  double? get mapLng => lastScannedLng ?? firstScannedLng;

  factory QrCodeModel.fromJson(Map<String, dynamic> json) {
    final nested = json['qr_codes'];
    final row = nested is Map<String, dynamic>
        ? nested
        : (nested is Map ? Map<String, dynamic>.from(nested) : json);

    final membership = json['membership'] is Map
        ? Map<String, dynamic>.from(json['membership'] as Map)
        : (nested != null ? json : null);

    bool hasMem = false;
    String? custom;
    bool pinned = row['is_pinned'] as bool? ?? false;
    int mine = 0;

    if (membership != null &&
        (membership.containsKey('my_scan_count') ||
            membership.containsKey('custom_label') ||
            nested != null)) {
      hasMem = membership['qr_code_id'] != null ||
          membership['my_scan_count'] != null ||
          nested != null;
      custom = membership['custom_label'] as String?;
      if (membership['is_pinned'] != null) {
        pinned = membership['is_pinned'] as bool;
      }
      mine = membership['my_scan_count'] as int? ?? 0;
    }

    final community = row['public_scan_count'] as int? ??
        row['scan_count'] as int? ??
        0;

    return QrCodeModel(
      id: row['id'] as String,
      userId: row['user_id'] as String,
      label: row['label'] as String,
      type: QrCodeType.values.firstWhere(
        (e) => e.name == row['type'],
        orElse: () => QrCodeType.text,
      ),
      content: row['content'] as String,
      source: QrCodeSource.values.firstWhere(
        (e) => e.name == row['source'],
        orElse: () => QrCodeSource.created,
      ),
      foregroundColor: row['foreground_color'] as String? ?? '#000000',
      backgroundColor: row['background_color'] as String? ?? '#FFFFFF',
      isPinned: pinned,
      isPublic: row['is_public'] as bool? ?? false,
      scanCount: row['scan_count'] as int? ?? community,
      publicScanCount: community,
      myScanCount: mine,
      customLabel: custom,
      hasMembership: hasMem,
      hasDate: row['has_date'] as bool? ?? false,
      hasParts: row['has_parts'] as bool? ?? false,
      payloadTemplate: row['payload_template'] as String?,
      firstScannedAt: row['first_scanned_at'] != null
          ? DateTime.parse(row['first_scanned_at'] as String)
          : null,
      lastScannedAt: row['last_scanned_at'] != null
          ? DateTime.parse(row['last_scanned_at'] as String)
          : null,
      firstScannedLat: (row['first_scanned_lat'] as num?)?.toDouble(),
      firstScannedLng: (row['first_scanned_lng'] as num?)?.toDouble(),
      firstScannedPlace: row['first_scanned_place'] as String?,
      lastScannedLat: (row['last_scanned_lat'] as num?)?.toDouble(),
      lastScannedLng: (row['last_scanned_lng'] as num?)?.toDouble(),
      lastScannedPlace: row['last_scanned_place'] as String?,
      createdAt: DateTime.parse(row['created_at'] as String),
      updatedAt: DateTime.parse(row['updated_at'] as String),
    );
  }

  factory QrCodeModel.fromScanRpc(Map<String, dynamic> json) {
    final codeMap = json['code'] is Map
        ? Map<String, dynamic>.from(json['code'] as Map)
        : json;
    final mem = json['membership'];
    if (mem is Map) {
      return QrCodeModel.fromJson({
        ...codeMap,
        'membership': mem,
      });
    }
    return QrCodeModel.fromJson(codeMap);
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'user_id': userId,
        'label': label,
        'type': type.name,
        'content': content,
        'source': source.name,
        'foreground_color': foregroundColor,
        'background_color': backgroundColor,
        'is_pinned': isPinned,
        'is_public': isPublic,
        'has_date': hasDate,
        'has_parts': hasParts,
        'payload_template': payloadTemplate,
        'scan_count': scanCount,
        'public_scan_count': publicScanCount,
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

  QrCodeModel copyWith({
    String? id,
    String? userId,
    String? label,
    QrCodeType? type,
    String? content,
    QrCodeSource? source,
    String? foregroundColor,
    String? backgroundColor,
    bool? isPinned,
    bool? isPublic,
    int? scanCount,
    int? publicScanCount,
    int? myScanCount,
    String? customLabel,
    bool clearCustomLabel = false,
    bool? hasMembership,
    bool? hasDate,
    bool? hasParts,
    String? payloadTemplate,
    bool clearPayloadTemplate = false,
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
        isPinned: isPinned ?? this.isPinned,
        isPublic: isPublic ?? this.isPublic,
        scanCount: scanCount ?? this.scanCount,
        publicScanCount: publicScanCount ?? this.publicScanCount,
        myScanCount: myScanCount ?? this.myScanCount,
        customLabel: clearCustomLabel ? null : (customLabel ?? this.customLabel),
        hasMembership: hasMembership ?? this.hasMembership,
        hasDate: hasDate ?? this.hasDate,
        hasParts: hasParts ?? this.hasParts,
        payloadTemplate: clearPayloadTemplate
            ? null
            : (payloadTemplate ?? this.payloadTemplate),
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

class QrCodeNote {
  final String id;
  final String qrCodeId;
  final String userId;
  final String body;
  final DateTime createdAt;

  const QrCodeNote({
    required this.id,
    required this.qrCodeId,
    required this.userId,
    required this.body,
    required this.createdAt,
  });

  factory QrCodeNote.fromJson(Map<String, dynamic> json) => QrCodeNote(
        id: json['id'] as String,
        qrCodeId: json['qr_code_id'] as String,
        userId: json['user_id'] as String,
        body: json['body'] as String,
        createdAt: DateTime.parse(json['created_at'] as String),
      );
}
