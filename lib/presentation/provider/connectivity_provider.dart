import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/legacy.dart';

class OnlineNotifier extends StateNotifier<bool> {
  OnlineNotifier() : super(true) {
    _init();
  }

  final Connectivity _conn = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _sub;

  Future<void> _init() async {
    final List<ConnectivityResult> initial = await _conn.checkConnectivity();
    if (!mounted) return;
    state = initial.any(_isOnline);
    _sub = _conn.onConnectivityChanged.listen((List<ConnectivityResult> results) {
      if (!mounted) return;
      state = results.any(_isOnline);
    });
  }

  bool _isOnline(ConnectivityResult r) => r != ConnectivityResult.none;

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}

final onlineProvider = StateNotifierProvider<OnlineNotifier, bool>((ref) => OnlineNotifier());