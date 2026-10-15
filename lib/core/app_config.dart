class AppConfig {
  // Pinned with --dart-define=API_BASE_URL=... (dev runs pin 127.0.0.1).
  // A relative value ("/api") means "the server this page came from" — for a
  // build served by the API itself or behind a reverse proxy.
  // Left empty, the API is reached on the same host the page was opened from,
  // so the session cookie stays same-site whichever address people use.
  static String apiBaseUrl = _resolveApiBaseUrl();

  static const apiPort = 4340;

  static String _resolveApiBaseUrl() {
    const pinned = String.fromEnvironment('API_BASE_URL');
    if (pinned.startsWith('/')) {
      final page = Uri.base;
      return '${page.scheme}://${page.authority}$pinned';
    }
    if (pinned.isNotEmpty) return pinned;
    final page = Uri.base;
    final host = page.host.isNotEmpty ? page.host : '127.0.0.1';
    final scheme = page.scheme == 'https' ? 'https' : 'http';
    return '$scheme://$host:$apiPort/api';
  }

  /// Signed out after this long without a mouse move or key press.
  static const idleTimeoutMinutes = 30;
}
