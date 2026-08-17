import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/local/local_store.dart';
import '../data/remote/supabase_bootstrap.dart';
import '../models/user.dart';

/// Auth + profile resolution.
///
/// When Supabase is configured, users sign in with password auth and the
/// authenticated profile is mirrored locally. In local mode the app signs
/// in as the device's local Administrator so every function works offline.
class AuthService {
  AuthService({required LocalStore localStore}) : _store = localStore;

  final LocalStore _store;

  bool get isLocalMode => !SupabaseBootstrap.isConfigured;

  /// The signed-in user's local profile (Administrator in local mode).
  Future<UserProfile> currentUser() async {
    final users = await _store.getUsers();
    if (users.isNotEmpty) return users.firstWhere((u) => u.active, orElse: () => users.first);
    return _createLocalAdministrator();
  }

  Future<UserProfile> _createLocalAdministrator() async {
    const profile = UserProfile(
      id: 'user_local_admin',
      authUserId: 'local',
      displayName: 'Administrator',
      role: UserRole.superAdmin,
      active: true,
    );
    await _store.putUser(profile);
    return profile;
  }

  /// Signs the user in. In local mode, creates the local Administrator
  /// profile on first run.
  Future<UserProfile> signIn({String? email, String? password}) async {
    if (isLocalMode) {
      return currentUser();
    }
    if (!SupabaseBootstrap.isInitialized) {
      await SupabaseBootstrap.initialize();
    }
    final auth = Supabase.instance.client.auth;
    final res = await auth.signInWithPassword(
      email: email ?? '',
      password: password ?? '',
    );
    final user = res.user;
    if (user == null) {
      throw Exception('Sign-in failed: no user session returned.');
    }

    // Mirror the authenticated profile locally so offline operation works.
    final existing = await _store.getUserByAuthId(user.id);
    if (existing != null) {
      await _store.putUser(existing);
      return existing;
    }
    final profile = UserProfile(
      id: 'user_${user.id.replaceAll('-', '').substring(0, 16)}',
      authUserId: user.id,
      displayName: user.userMetadata?['full_name'] as String? ?? user.email ?? 'User',
      role: UserRole.staff,
      active: true,
      createdAt: DateTime.now().toUtc(),
    );
    await _store.putUser(profile);
    return profile;
  }

  Future<void> signOut() async {
    if (!isLocalMode && SupabaseBootstrap.isInitialized) {
      await Supabase.instance.client.auth.signOut();
    }
  }
}