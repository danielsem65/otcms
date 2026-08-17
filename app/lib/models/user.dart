/// Roles and the authenticated profile model.
///
/// Roles/permissions are enforced server-side (RLS + definer RPCs).
/// The client only uses them to shape the UI.
enum UserRole {
  superAdmin('SUPER_ADMIN'),
  owner('OWNER'),
  admin('ADMIN'),
  pharmacist('PHARMACIST'),
  inventoryManager('INVENTORY_MANAGER'),
  cashier('CASHIER'),
  staff('STAFF');

  const UserRole(this.dbValue);
  final String dbValue;

  static UserRole fromDb(String? value) => UserRole.values
      .firstWhere((e) => e.dbValue == value, orElse: () => UserRole.staff);

  String get label => switch (this) {
        UserRole.superAdmin => 'Super Admin',
        UserRole.owner => 'Owner',
        UserRole.admin => 'Admin',
        UserRole.pharmacist => 'Pharmacist',
        UserRole.inventoryManager => 'Inventory Manager',
        UserRole.cashier => 'Cashier',
        UserRole.staff => 'Staff',
      };
}

/// UI-shaping permission set (authorization is enforced in the database).
class Permissions {
  static const viewProducts = 'view_products';
  static const createProduct = 'create_product';
  static const editProduct = 'edit_product';
  static const createSale = 'create_sale';
  static const viewSales = 'view_sales';
  static const adjustStock = 'adjust_stock';
  static const receiveStock = 'receive_stock';
  static const createPurchase = 'create_purchase';
  static const approvePurchase = 'approve_purchase';
  static const viewReports = 'view_reports';
  static const manageUsers = 'manage_users';
  static const manageSettings = 'manage_settings';
  static const viewStockCounts = 'view_stock_counts';
  static const viewExpiry = 'view_expiry';
}

/// The user profile: mirrors `profiles` in Supabase.
class UserProfile {
  const UserProfile({
    required this.id,
    this.authUserId,
    this.organizationId,
    this.branchId,
    this.role = UserRole.staff,
    required this.displayName,
    this.phone,
    this.active = true,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String? authUserId;
  final String? organizationId;
  final String? branchId;
  final UserRole role;
  final String displayName;
  final String? phone;
  final bool active;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool hasPermission(String permission) {
    if (role == UserRole.superAdmin || role == UserRole.owner) return true;
    final list = _rolePermissions[role];
    return list != null && list.contains(permission);
  }

  static const Map<UserRole, List<String>> _rolePermissions = {
    UserRole.admin: [
      Permissions.viewProducts, Permissions.createProduct, Permissions.editProduct,
      Permissions.createSale, Permissions.viewSales, Permissions.adjustStock,
      Permissions.receiveStock, Permissions.createPurchase, Permissions.approvePurchase,
      Permissions.viewReports, Permissions.manageUsers, Permissions.manageSettings,
      Permissions.viewStockCounts, Permissions.viewExpiry,
    ],
    UserRole.pharmacist: [
      Permissions.viewProducts, Permissions.createProduct, Permissions.editProduct,
      Permissions.createSale, Permissions.viewSales, Permissions.adjustStock,
      Permissions.receiveStock, Permissions.createPurchase, Permissions.viewReports,
      Permissions.viewStockCounts, Permissions.viewExpiry,
    ],
    UserRole.inventoryManager: [
      Permissions.viewProducts, Permissions.createProduct, Permissions.editProduct,
      Permissions.viewSales, Permissions.adjustStock, Permissions.receiveStock,
      Permissions.createPurchase, Permissions.approvePurchase, Permissions.viewStockCounts,
      Permissions.viewExpiry,
    ],
    UserRole.cashier: [Permissions.viewProducts, Permissions.createSale, Permissions.viewSales],
    UserRole.staff: [Permissions.viewProducts, Permissions.createSale],
  };

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
        id: json['id'] as String,
        authUserId: json['authUserId'] as String?,
        organizationId: json['organizationId'] as String?,
        branchId: json['branchId'] as String?,
        role: UserRole.fromDb(json['role'] as String?),
        displayName: json['displayName'] as String,
        phone: json['phone'] as String?,
        active: (json['active'] as bool?) ?? true,
        createdAt: _parseUtc(json['createdAt']),
        updatedAt: _parseUtc(json['updatedAt']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'authUserId': authUserId,
        'organizationId': organizationId,
        'branchId': branchId,
        'role': role.dbValue,
        'displayName': displayName,
        'phone': phone,
        'active': active,
        'createdAt': createdAt?.toUtc().toIso8601String(),
        'updatedAt': updatedAt?.toUtc().toIso8601String(),
      };

  static DateTime? _parseUtc(dynamic value) =>
      value == null ? null : DateTime.tryParse(value.toString())?.toUtc();
}
