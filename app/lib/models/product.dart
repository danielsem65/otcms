/// Product + Category domain models.
class Product {
  const Product({
    required this.id,
    this.organizationId,
    this.branchId,
    required this.name,
    this.genericName,
    this.brandName,
    this.categoryId,
    this.dosageForm,
    this.strength,
    this.packSize,
    this.barcode,
    this.sku,
    this.manufacturer,
    this.responsible,
    required this.sellingPricePesewas,
    this.costPricePesewas,
    this.reorderLevel = 10,
    this.minimumStock = 5,
    this.targetStock = 50,
    this.reorderQuantity = 20,
    this.active = true,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String? organizationId;
  final String? branchId;
  final String name;
  final String? genericName;
  final String? brandName;
  final String? categoryId;
  final String? dosageForm;
  final String? strength;
  final String? packSize;
  final String? barcode;
  final String? sku;
  final String? manufacturer;
  final String? responsible;
  final int sellingPricePesewas;
  final int? costPricePesewas;
  final int reorderLevel;
  final int minimumStock;
  final int targetStock;
  final int reorderQuantity;
  final bool active;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  Product copyWith({
    String? name,
    String? genericName,
    String? brandName,
    String? categoryId,
    String? dosageForm,
    String? strength,
    String? packSize,
    String? barcode,
    String? sku,
    String? manufacturer,
    String? responsible,
    int? sellingPricePesewas,
    int? costPricePesewas,
    int? reorderLevel,
    int? minimumStock,
    int? targetStock,
    int? reorderQuantity,
    bool? active,
    DateTime? updatedAt,
  }) =>
      Product(
        id: id,
        organizationId: organizationId,
        branchId: branchId,
        name: name ?? this.name,
        genericName: genericName ?? this.genericName,
        brandName: brandName ?? this.brandName,
        categoryId: categoryId ?? this.categoryId,
        dosageForm: dosageForm ?? this.dosageForm,
        strength: strength ?? this.strength,
        packSize: packSize ?? this.packSize,
        barcode: barcode ?? this.barcode,
        sku: sku ?? this.sku,
        manufacturer: manufacturer ?? this.manufacturer,
        responsible: responsible ?? this.responsible,
        sellingPricePesewas: sellingPricePesewas ?? this.sellingPricePesewas,
        costPricePesewas: costPricePesewas ?? this.costPricePesewas,
        reorderLevel: reorderLevel ?? this.reorderLevel,
        minimumStock: minimumStock ?? this.minimumStock,
        targetStock: targetStock ?? this.targetStock,
        reorderQuantity: reorderQuantity ?? this.reorderQuantity,
        active: active ?? this.active,
        createdAt: createdAt,
        updatedAt: updatedAt ?? DateTime.now().toUtc(),
      );

  factory Product.fromJson(Map<String, dynamic> json) => Product(
        id: json['id'] as String,
        organizationId: json['organizationId'] as String?,
        branchId: json['branchId'] as String?,
        name: json['name'] as String,
        genericName: json['genericName'] as String?,
        brandName: json['brandName'] as String?,
        categoryId: json['categoryId'] as String?,
        dosageForm: json['dosageForm'] as String?,
        strength: json['strength'] as String?,
        packSize: json['packSize'] as String?,
        barcode: json['barcode'] as String?,
        sku: json['sku'] as String?,
        manufacturer: json['manufacturer'] as String?,
        responsible: json['responsible'] as String?,
        sellingPricePesewas: json['sellingPricePesewas'] as int,
        costPricePesewas: json['costPricePesewas'] as int?,
        reorderLevel: (json['reorderLevel'] as int?) ?? 10,
        minimumStock: (json['minimumStock'] as int?) ?? 5,
        targetStock: (json['targetStock'] as int?) ?? 50,
        reorderQuantity: (json['reorderQuantity'] as int?) ?? 20,
        active: (json['active'] as bool?) ?? true,
        createdAt: _parseUtc(json['createdAt']),
        updatedAt: _parseUtc(json['updatedAt']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'organizationId': organizationId,
        'branchId': branchId,
        'name': name,
        'genericName': genericName,
        'brandName': brandName,
        'categoryId': categoryId,
        'dosageForm': dosageForm,
        'strength': strength,
        'packSize': packSize,
        'barcode': barcode,
        'sku': sku,
        'manufacturer': manufacturer,
        'responsible': responsible,
        'sellingPricePesewas': sellingPricePesewas,
        'costPricePesewas': costPricePesewas,
        'reorderLevel': reorderLevel,
        'minimumStock': minimumStock,
        'targetStock': targetStock,
        'reorderQuantity': reorderQuantity,
        'active': active,
        'createdAt': createdAt?.toUtc().toIso8601String(),
        'updatedAt': updatedAt?.toUtc().toIso8601String(),
      };

  static DateTime? _parseUtc(dynamic value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString())?.toUtc();
  }

  /// Quick search fields used by the product search service.
  List<String> get searchTokens => [
        name,
        if (genericName != null) genericName!,
        if (brandName != null) brandName!,
        if (barcode != null) barcode!,
        if (sku != null) sku!,
        if (manufacturer != null) manufacturer!,
      ].map((e) => e.toUpperCase()).toList();
}

class Category {
  const Category({
    required this.id,
    this.organizationId,
    required this.name,
    this.description,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String? organizationId;
  final String name;
  final String? description;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory Category.fromJson(Map<String, dynamic> json) => Category(
        id: json['id'] as String,
        organizationId: json['organizationId'] as String?,
        name: json['name'] as String,
        description: json['description'] as String?,
        createdAt: _parseUtc(json['createdAt']),
        updatedAt: _parseUtc(json['updatedAt']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'organizationId': organizationId,
        'name': name,
        'description': description,
        'createdAt': createdAt?.toUtc().toIso8601String(),
        'updatedAt': updatedAt?.toUtc().toIso8601String(),
      };

  static DateTime? _parseUtc(dynamic value) =>
      value == null ? null : DateTime.tryParse(value.toString())?.toUtc();
}
