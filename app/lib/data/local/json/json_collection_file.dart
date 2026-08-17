import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// A JSON collection file with atomic writes and write-behind debouncing.
///
/// Each collection lives in its own file:
/// `{ "schemaVersion": 1, "items": [...] }`.
///
/// Writes go through a serialized queue and are debounced: rapid mutations
/// coalesce into a single disk write. Each write is atomic (tmp file +
/// rename), so a crash can never leave a half-written collection.
class JsonCollectionFile<T> {
  JsonCollectionFile({
    required this.path,
    required this.fromJson,
    required this.toJson,
    this.schemaVersion = 1,
  });

  final String path;
  final T Function(Map<String, dynamic>) fromJson;
  final Map<String, dynamic> Function(T) toJson;
  final int schemaVersion;

  bool _loaded = false;
  Map<String, T> _items = {};
  Timer? _debounce;
  final _writeQueue = <Future<void> Function()>[];
  bool _writerRunning = false;
  bool _dirty = false;

  int get length => _items.length;

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    final file = File(path);
    if (await file.exists()) {
      try {
        final raw = await file.readAsString();
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        final items = decoded['items'] as List<dynamic>? ?? [];
        final parsed = items.cast<Map<String, dynamic>>().map(fromJson).toList();
        _items = {for (final item in parsed) fromJsonKey(item): item};
      } catch (e) {
        // Corrupt or truncated file. Do not crash: treat as empty and
        // schedule an immediate rewrite so a healthy file is restored.
        _items = {};
        _scheduleWrite(immediate: true);
      }
    }
    _loaded = true;
  }

  Future<List<T>> getAll() async {
    await _ensureLoaded();
    return _items.values.toList();
  }

  Future<T?> getById(String Function(T) idOf, String id) async {
    await _ensureLoaded();
    for (final item in _items.values) {
      if (idOf(item) == id) return item;
    }
    return null;
  }

  Future<bool> any(bool Function(T) test) async {
    await _ensureLoaded();
    return _items.values.any(test);
  }

  Future<void> put(T item, {String Function(T)? keyOf}) async {
    await _ensureLoaded();
    _items[keyOf != null ? keyOf(item) : fromJsonKey(item)] = item;
    _scheduleWrite();
  }

  Future<void> putAll(List<T> items, {String Function(T)? keyOf}) async {
    await _ensureLoaded();
    for (final item in items) {
      _items[keyOf != null ? keyOf(item) : fromJsonKey(item)] = item;
    }
    _scheduleWrite();
  }

  Future<void> removeWhere(bool Function(T) test, {String Function(T)? keyOf}) async {
    await _ensureLoaded();
    final keys = <String>[];
    for (final entry in _items.entries) {
      if (test(entry.value)) keys.add(keyOf != null ? keyOf(entry.value) : entry.key);
    }
    for (final k in keys) {
      _items.remove(k);
    }
    if (keys.isNotEmpty) _scheduleWrite();
  }

  Future<void> replaceAll(List<T> items, {String Function(T)? keyOf}) async {
    await _ensureLoaded();
    _items = {
      for (final item in items) (keyOf != null ? keyOf(item) : fromJsonKey(item)): item,
    };
    _scheduleWrite();
  }

  String fromJsonKey(T item) => toJson(item)['id'] as String;

  void _scheduleWrite({bool immediate = false}) {
    _dirty = true;
    if (immediate) {
      _debounce?.cancel();
      _enqueueWrite();
      return;
    }
    _debounce ??= Timer(const Duration(milliseconds: 250), _enqueueWrite);
  }

  void _enqueueWrite() {
    _debounce?.cancel();
    _debounce = null;
    if (!_dirty) return;
    _writeQueue.add(() => _persist());
    _drain();
  }

  Future<void> _drain() async {
    if (_writerRunning) return;
    _writerRunning = true;
    try {
      while (_writeQueue.isNotEmpty) {
        final task = _writeQueue.removeAt(0);
        await task();
      }
    } finally {
      _writerRunning = false;
    }
  }

  Future<void> _persist() async {
    if (!_dirty) return;
    _dirty = false;
    final tmp = File('$path.tmp');
    final target = File(path);
    try {
      await target.parent.create(recursive: true);
      final payload = jsonEncode({
        'schemaVersion': schemaVersion,
        'items': _items.values.map(toJson).toList(),
      });
      await tmp.writeAsString(payload, flush: true);
      await tmp.rename(target.path);
    } catch (_) {
      // Keep dirty so the next schedule retries; the in-memory copy is
      // still authoritative for this session.
      _dirty = true;
    }
  }

  /// Flushes pending writes immediately (used before backup/shutdown).
  Future<void> flush() async {
    _debounce?.cancel();
    _debounce = null;
    await _persist();
    await _drain();
  }
}
