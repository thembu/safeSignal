import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

void _log(String msg) {
  // ignore: avoid_print
  if (kDebugMode) print('[ShareIntake] $msg');
}

/// Wraps receive_sharing_intent. Emits trip links (Uber/Bolt or any URL)
/// shared into the app, both cold-start and while-running.
///
/// Also parks a "pending" link that survives auth — so if the user shares
/// before signing in, HomeScreen can consume it after AuthGate lets them in.
class ShareIntakeService {
  ShareIntakeService._();
  static final instance = ShareIntakeService._();

  final _controller = StreamController<String>.broadcast();
  StreamSubscription<List<SharedMediaFile>>? _sub;
  String? _pendingLink;
  bool _initialised = false;

  /// Broadcast stream of incoming trip links.
  Stream<String> get links => _controller.stream;

  /// Link captured before a consumer was ready (e.g. cold-start pre-auth).
  /// Read once, then cleared.
  String? consumePending() {
    final link = _pendingLink;
    _pendingLink = null;
    return link;
  }

  bool get hasPending => _pendingLink != null;

  Future<void> init() async {
    if (_initialised) return;
    _initialised = true;

    // Cold-start: app was launched by a share intent.
    final initial = await ReceiveSharingIntent.instance.getInitialMedia();
    _handleShared(initial, source: 'initial');
    // Tell the plugin we've consumed the initial payload so it doesn't replay.
    ReceiveSharingIntent.instance.reset();

    // Runtime: app was already alive when the user shared.
    _sub = ReceiveSharingIntent.instance.getMediaStream().listen(
          (media) => _handleShared(media, source: 'stream'),
      onError: (e) => _log('stream error: $e'),
    );
  }

  void _handleShared(List<SharedMediaFile> media, {required String source}) {
    if (media.isEmpty) return;
    for (final m in media) {
      final raw = m.path;
      _log('$source: got "${_truncate(raw)}" (type=${m.type})');
      final url = _extractUrl(raw);
      if (url == null) {
        _log('$source: no URL found, skipping');
        continue;
      }
      _log('$source: extracted url=$url');
      // Always park — EhailingScreen consumes it on mount via consumePending().
      _pendingLink = url;
      // Also broadcast — a listener already on screen (e.g. HomeScreen or an
      // already-mounted EhailingScreen) can react immediately.
      _controller.add(url);
    }
  }
  /// Pulls the first http(s) URL out of a shared string. Share sheets often
  /// deliver "Track my ride: https://uber.com/…" rather than a bare URL.
  static String? _extractUrl(String text) {
    final match = RegExp(r'https?://\S+').firstMatch(text);
    return match?.group(0);
  }

  static String _truncate(String s) =>
      s.length > 120 ? '${s.substring(0, 120)}…' : s;

  Future<void> dispose() async {
    await _sub?.cancel();
    await _controller.close();
  }
}