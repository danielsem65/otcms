/// Pharmacy settings + pharmacy profile (shown on invoices).
class PharmacySettings {
  const PharmacySettings({
    this.pharmacyName = 'Agya Appiah OTCMS',
    this.address = '',
    this.phone = '',
    this.email = '',
    this.currencyCode = 'GHS',
    this.currencySymbol = '₵',
    this.timezone = 'Africa/Accra',
    this.expiryWarningDays = const [7, 30, 60, 90, 180],
    this.lowStockDaysBack = 14,
    this.autoBackupDays = 7,
    this.dataDirectory = '',
    this.notifyBeforeDays = const [7, 30, 60, 90],
  });

  factory PharmacySettings.fromJson(Map<String, dynamic> json) => PharmacySettings(
        pharmacyName: json['pharmacyName'] as String? ?? 'Agya Appiah OTCMS',
        address: json['address'] as String? ?? '',
        phone: json['phone'] as String? ?? '',
        email: json['email'] as String? ?? '',
        currencyCode: json['currencyCode'] as String? ?? 'GHS',
        currencySymbol: json['currencySymbol'] as String? ?? '₵',
        timezone: json['timezone'] as String? ?? 'Africa/Accra',
        expiryWarningDays: (json['expiryWarningDays'] as List<dynamic>?)
                ?.map((e) => e as int)
                .toList() ??
            const [7, 30, 60, 90, 180],
        lowStockDaysBack: (json['lowStockDaysBack'] as int?) ?? 14,
        autoBackupDays: (json['autoBackupDays'] as int?) ?? 7,
        dataDirectory: json['dataDirectory'] as String? ?? '',
        notifyBeforeDays: (json['notifyBeforeDays'] as List<dynamic>?)
                ?.map((e) => e as int)
                .toList() ??
            const [7, 30, 60, 90],
      );

  final String pharmacyName;
  final String address;
  final String phone;
  final String email;
  final String currencyCode;
  final String currencySymbol;
  final String timezone;

  /// Expiry alert thresholds in days (sorted ascending).
  final List<int> expiryWarningDays;

  /// How many days of sales history are used for velocity estimates.
  final int lowStockDaysBack;

  /// Automatic backup interval on desktop.
  final int autoBackupDays;

  /// Override for local data directory (desktop). Empty = default.
  final String dataDirectory;

  /// Lead days for Android local notifications (before expiry).
  final List<int> notifyBeforeDays;

  PharmacySettings copyWith({
    String? pharmacyName,
    String? address,
    String? phone,
    String? email,
    String? currencyCode,
    String? currencySymbol,
    String? timezone,
    List<int>? expiryWarningDays,
    int? lowStockDaysBack,
    int? autoBackupDays,
    String? dataDirectory,
    List<int>? notifyBeforeDays,
  }) =>
      PharmacySettings(
        pharmacyName: pharmacyName ?? this.pharmacyName,
        address: address ?? this.address,
        phone: phone ?? this.phone,
        email: email ?? this.email,
        currencyCode: currencyCode ?? this.currencyCode,
        currencySymbol: currencySymbol ?? this.currencySymbol,
        timezone: timezone ?? this.timezone,
        expiryWarningDays: expiryWarningDays ?? this.expiryWarningDays,
        lowStockDaysBack: lowStockDaysBack ?? this.lowStockDaysBack,
        autoBackupDays: autoBackupDays ?? this.autoBackupDays,
        dataDirectory: dataDirectory ?? this.dataDirectory,
        notifyBeforeDays: notifyBeforeDays ?? this.notifyBeforeDays,
      );

  Map<String, dynamic> toJson() => {
        'pharmacyName': pharmacyName,
        'address': address,
        'phone': phone,
        'email': email,
        'currencyCode': currencyCode,
        'currencySymbol': currencySymbol,
        'timezone': timezone,
        'expiryWarningDays': expiryWarningDays,
        'lowStockDaysBack': lowStockDaysBack,
        'autoBackupDays': autoBackupDays,
        'dataDirectory': dataDirectory,
        'notifyBeforeDays': notifyBeforeDays,
      };
}

/// Pharmacy profile (name/address/phone) shown on invoices and settings.
class PharmacyProfile {
  const PharmacyProfile({
    required this.id,
    this.organizationId,
    required this.name,
    this.address,
    this.phone,
    this.email,
    this.logoPath,
    this.createdAt,
    this.updatedAt,
  });

  factory PharmacyProfile.fromJson(Map<String, dynamic> json) => PharmacyProfile(
        id: json['id'] as String,
        organizationId: json['organizationId'] as String?,
        name: json['name'] as String,
        address: json['address'] as String?,
        phone: json['phone'] as String?,
        email: json['email'] as String?,
        logoPath: json['logoPath'] as String?,
        createdAt: _parseUtc(json['createdAt']),
        updatedAt: _parseUtc(json['updatedAt']),
      );

  final String id;
  final String? organizationId;
  final String name;
  final String? address;
  final String? phone;
  final String? email;
  final String? logoPath;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  PharmacyProfile copyWith({
    String? name,
    String? address,
    String? phone,
    String? email,
    String? logoPath,
  }) =>
      PharmacyProfile(
        id: id,
        organizationId: organizationId,
        name: name ?? this.name,
        address: address ?? this.address,
        phone: phone ?? this.phone,
        email: email ?? this.email,
        logoPath: logoPath ?? this.logoPath,
        createdAt: createdAt,
        updatedAt: DateTime.now().toUtc(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'organizationId': organizationId,
        'name': name,
        'address': address,
        'phone': phone,
        'email': email,
        'logoPath': logoPath,
        'createdAt': createdAt?.toUtc().toIso8601String(),
        'updatedAt': updatedAt?.toUtc().toIso8601String(),
      };

  static DateTime? _parseUtc(dynamic value) =>
      value == null ? null : DateTime.tryParse(value.toString())?.toUtc();
}
