/// Remote app settings from `config/app` in Firestore, set by the developer
/// in the Firebase console. Missing or unreadable means "no requirement".
class AppConfig {
  const AppConfig({
    this.minBuild = 0,
    this.latestBuild = 0,
    this.message,
    this.updateUrl,
  });

  /// Builds below this must update before they can play (forced update).
  final int minBuild;

  /// Builds below this are offered an optional update.
  final int latestBuild;

  /// Optional text shown on the update screen ("New: emoji chat!").
  final String? message;

  /// Where "Update" goes when Google Play's in-app update isn't available
  /// (e.g. the GitHub releases page). Defaults to the Play Store listing.
  final String? updateUrl;

  static const none = AppConfig();

  factory AppConfig.fromMap(Map<String, dynamic>? m) {
    int n(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
    String? str(Object? v) =>
        v is String && v.trim().isNotEmpty ? v.trim() : null;
    return AppConfig(
      minBuild: n(m?['minBuild']),
      latestBuild: n(m?['latestBuild']),
      message: str(m?['message']),
      updateUrl: str(m?['updateUrl']),
    );
  }
}
