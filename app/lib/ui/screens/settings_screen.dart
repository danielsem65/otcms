import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ids.dart';
import '../../models/settings.dart';
import '../../state/providers.dart';

/// Pharmacy settings: business info (shown on invoices) + catalog import.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _name = TextEditingController();
  final _address = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  bool _initialized = false;
  bool _saving = false;
  bool _importing = false;

  @override
  void dispose() {
    _name.dispose();
    _address.dispose();
    _phone.dispose();
    _email.dispose();
    super.dispose();
  }

  void _populateFrom(PharmacyProfile? pharmacy) {
    _name.text = pharmacy?.name ?? '';
    _address.text = pharmacy?.address ?? '';
    _phone.text = pharmacy?.phone ?? '';
    _email.text = pharmacy?.email ?? '';
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final store = ref.read(localStoreProvider);
      final pharmacy = ref.read(pharmacyProvider).valueOrNull;
      final updated =
          (pharmacy ?? PharmacyProfile(id: Ids.newId('pharm'), name: 'OTCMS')).copyWith(
        name: _name.text.trim().isEmpty ? 'OTCMS' : _name.text.trim(),
        address: _address.text.trim(),
        phone: _phone.text.trim(),
        email: _email.text.trim(),
      );
      await store.savePharmacy(updated);
      final settings = await store.getSettings();
      await store.saveSettings(settings.copyWith(
        pharmacyName: updated.name,
        address: updated.address,
        phone: updated.phone,
        email: updated.email,
      ));
      ref.invalidate(pharmacyProvider);
      ref.invalidate(settingsProvider);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Settings saved.')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _importFromFile() async {
    if (_importing) return;
    setState(() => _importing = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      if (result == null || result.files.isEmpty) return;
      final path = result.files.single.path;
      if (path == null) return;

      final file = await File(path).readAsString();
      final service = ref.read(productImportServiceProvider);
      final outcome = await service.importJson(file);
      if (mounted) {
        if (outcome.isOk) {
          final s = outcome.value;
          await _showImportResult(s.totalRead, s.imported, s.skippedInvalid);
        } else {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(outcome.error.message)));
        }
      }
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _showImportResult(int total, int imported, int skipped) async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Import complete'),
        content: Text(
          'Products read: $total\n'
          'Imported / updated: $imported\n'
          'Skipped (invalid): $skipped',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pharmacy = ref.watch(pharmacyProvider).valueOrNull;
    if (!_initialized && pharmacy != null) {
      _initialized = true;
      _populateFrom(pharmacy);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('PHARMACY INFORMATION',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1.2)),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _field(_name, 'Pharmacy name', icon: Icons.storefront),
                  _field(_address, 'Address', icon: Icons.place_outlined),
                  _field(_phone, 'Phone', icon: Icons.call_outlined, keyboard: TextInputType.phone),
                  _field(_email, 'Email', icon: Icons.mail_outline,
                      keyboard: TextInputType.emailAddress),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      FilledButton(
                        onPressed: _saving ? null : _save,
                        child: Text(_saving ? 'Saving…' : 'Save'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text('PRODUCT CATALOG',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1.2)),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Import products',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Import the pharmacy product list (Products.json). '
                    'Existing names are preserved exactly; prices are kept to the pesewa.',
                    style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    icon: _importing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.upload_file),
                    label: Text(_importing ? 'Importing…' : 'Choose JSON file…'),
                    onPressed: _importing ? null : _importFromFile,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _field(TextEditingController controller, String label,
      {IconData? icon, TextInputType? keyboard}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        keyboardType: keyboard,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: icon == null ? null : Icon(icon),
        ),
      ),
    );
  }
}