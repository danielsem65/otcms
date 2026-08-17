import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

/// Connection state exposed to the UI.
enum ConnectionStatus {
  online,
  offline,
  unknown;

  bool get isOnline => this == ConnectionStatus.online;
}

/// Watches connectivity and notifies listeners.
///
/// The app never depends on this for correctness — everything works
/// locally — but it drives the sync engine and the status banner.
class ConnectivityService {
  ConnectivityService({Connectivity? connectivity})
      : _connectivity = connectivity ?? Connectivity();

  final Connectivity _connectivity;

  final _controller = StreamController<ConnectionStatus>.broadcast();
  ConnectionStatus _status = ConnectionStatus.unknown;
  StreamSubscription<List<ConnectivityResult>>? _subscription;

  ConnectionStatus get status => _status;

  Stream<ConnectionStatus> get stream => _controller.stream;

  Future<void> start() async {
    try {
      final results = await _connectivity.checkConnectivity();
      _subscription = _connectivity.onConnectivityChanged.listen(
        _onChanged,
        onError: (Object _) {
          // No connectivity plugin available (tests, unsupported platform):
          // fall through to checkConnectivity below, which ends in online.
        },
      );
      _onChanged(results);
    } catch (_) {
      // No connectivity plugin available (tests, unsupported platform):
      // assume online so the app behaves as local-capable.
      _status = ConnectionStatus.online;
    }
  }

  void _onChanged(List<ConnectivityResult> results) {
    final online = results.any((r) => r != ConnectivityResult.none);
    final next = online ? ConnectionStatus.online : ConnectionStatus.offline;
    if (next != _status) {
      _status = next;
      if (!_controller.isClosed) _controller.add(next);
    }
  }

  void dispose() {
    _subscription?.cancel();
    _controller.close();
  }
}