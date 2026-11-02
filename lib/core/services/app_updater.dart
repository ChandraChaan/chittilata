import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:in_app_update/in_app_update.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

/// Installs a newer version of the app.
abstract final class AppUpdater {
  static const packageId = 'com.chandra.chittilata';

  /// This install's build number (the `+N` in pubspec), or null if unknown.
  /// Replaced in tests.
  static Future<int?> Function() currentBuild = () async {
    try {
      return int.tryParse((await PackageInfo.fromPlatform()).buildNumber);
    } catch (_) {
      return null;
    }
  };

  /// Uses Google Play's in-app update when the app came from Play; otherwise
  /// opens [url] (if given) or the Play Store listing.
  static Future<void> update({String? url}) async {
    if (!kIsWeb && Platform.isAndroid && url == null) {
      try {
        final info = await InAppUpdate.checkForUpdate();
        if (info.updateAvailability == UpdateAvailability.updateAvailable &&
            info.immediateUpdateAllowed) {
          final r = await InAppUpdate.performImmediateUpdate();
          if (r == AppUpdateResult.success) return;
        }
      } catch (e) {
        // Not installed from Google Play (a test or GitHub build).
        debugPrint('in-app update unavailable: $e');
      }
    }
    final targets = [
      if (url != null) Uri.parse(url),
      Uri.parse('market://details?id=$packageId'),
      Uri.parse('https://play.google.com/store/apps/details?id=$packageId'),
    ];
    for (final u in targets) {
      try {
        if (await launchUrl(u, mode: LaunchMode.externalApplication)) return;
      } catch (_) {}
    }
  }
}
