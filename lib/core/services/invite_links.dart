import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';

/// Room invites as web links: `https://chittilata-game.web.app/join/ABC234`.
///
/// On Android the link opens the app directly (App Links); without the app
/// it shows a page with the code and a Play Store button. Incoming codes wait
/// in [pending] until the home screen can act on them.
class InviteLinks extends ChangeNotifier {
  static const host = 'chittilata-game.web.app';
  static final _code = RegExp(r'^[A-Za-z0-9]{6}$');

  static Uri linkFor(String code) => Uri.https(host, '/join/$code');
  static Uri groupLinkFor(String code) => Uri.https(host, '/group/$code');

  /// What friends receive to join a group.
  static String groupMessage(String name, String code) =>
      'Join our "$name" group on Chittilata! 👥\n'
      'Group code: $code\n'
      '${groupLinkFor(code)}';

  /// What friends receive in WhatsApp or any other app.
  static String message(String code) =>
      'Join my Chittilata game! 🎬👑\n'
      'Room code: $code\n'
      '${linkFor(code)}';

  /// The room code in an invite link, or null for any other link.
  static String? codeFrom(Uri uri) => _codeAt(uri, 'join');

  /// The group code in a group invite link.
  static String? groupCodeFrom(Uri uri) => _codeAt(uri, 'group');

  static String? _codeAt(Uri uri, String path) {
    if (uri.host != host) return null;
    final s = uri.pathSegments.where((p) => p.isNotEmpty).toList();
    if (s.length != 2 || s[0] != path || !_code.hasMatch(s[1])) return null;
    return s[1].toUpperCase();
  }

  String? _pending;
  String? _pendingGroup;
  StreamSubscription<Uri>? _sub;

  /// A group code from a link, waiting to be joined.
  String? get pendingGroup => _pendingGroup;

  String? takeGroup() {
    final c = _pendingGroup;
    _pendingGroup = null;
    return c;
  }

  /// A room code from a link that hasn't been joined yet.
  String? get pending => _pending;

  /// Listens for links that open the app (including the one it started from).
  Future<void> start() async {
    try {
      final appLinks = AppLinks();
      _sub = appLinks.uriLinkStream.listen(receive, onError: (_) {});
      final first = await appLinks.getInitialLink();
      if (first != null) receive(first);
    } catch (e) {
      debugPrint('invite links unavailable: $e');
    }
  }

  void receive(Uri uri) {
    final group = groupCodeFrom(uri);
    if (group != null && group != _pendingGroup) {
      _pendingGroup = group;
      notifyListeners();
      return;
    }
    final code = codeFrom(uri);
    if (code == null || code == _pending) return;
    _pending = code;
    notifyListeners();
  }

  /// Hands the pending code to whoever will join it.
  String? take() {
    final c = _pending;
    _pending = null;
    return c;
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
