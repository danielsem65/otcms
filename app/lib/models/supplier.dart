class Supplier {
  const Supplier({
    required this.id,
    this.organizationId,
    this.branchId,
    required this.name,
    this.phone,
    this.address,
    this.email,
    this.contactPerson,
    this.active = true,
    this.createdAt,
    this.updatedAt,
  });

  factory Supplier.fromJson(Map<String, dynamic> json) => Supplier(
        id: json['id'] as String,
        organizationId: json['organizationId'] as String?,
        branchId: json['branchId'] as String?,
        name: json['name'] as String,
        phone: json['phone'] as String?,
        address: json['address'] as String?,
        email: json['email'] as String?,
        contactPerson: json['contactPerson'] as String?,
        active: (json['active'] as bool?) ?? true,
        createdAt: _parseUtc(json['createdAt']),
        updatedAt: _parseUtc(json['updatedAt']),
      );

  final String id;
  final String? organizationId;
  final String? branchId;
  final String name;
  final String? phone;
  final String? address;
  final String? email;
  final String? contactPerson;
  final bool active;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  Supplier copyWith({
    String? name,
    String? phone,
    String? address,
    String? email,
    String? contactPerson,
    bool? active,
    DateTime? updatedAt,
  }) =>
      Supplier(
        id: id,
        organizationId: organizationId,
        branchId: branchId,
        name: name ?? this.name,
        phone: phone ?? this.phone,
        address: address ?? this.address,
        email: email ?? this.email,
        contactPerson: contactPerson ?? this.contactPerson,
        active: active ?? this.active,
        createdAt: createdAt,
        updatedAt: updatedAt ?? DateTime.now().toUtc(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'organizationId': organizationId,
        'branchId': branchId,
        'name': name,
        'phone': phone,
        'address': address,
        'email': email,
        'contactPerson': contactPerson,
        'active': active,
        'createdAt': createdAt?.toUtc().toIso8601String(),
        'updatedAt': updatedAt?.toUtc().toIso8601String(),
      };

  static DateTime? _parseUtc(dynamic value) =>
      value == null ? null : DateTime.tryParse(value.toString())?.toUtc();
}
