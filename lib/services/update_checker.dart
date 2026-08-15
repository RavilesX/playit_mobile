import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

/// GitHub repository the releases are published to.
const kRepoOwner = 'RavilesX';
const kRepoName = 'playit_mobile';
const kRepoUrl = 'https://github.com/$kRepoOwner/$kRepoName';

const _kLatestReleaseApi =
    'https://api.github.com/repos/$kRepoOwner/$kRepoName/releases/latest';

const _prefAutoCheck = 'update_auto_check';
const _prefLastCheck = 'update_last_check_ms';
const _prefSkippedVersion = 'update_skipped_version';

/// How long the silent startup check waits before hitting the API again.
const kAutoCheckInterval = Duration(hours: 24);

/// A release published on GitHub, as far as the app cares about it.
class ReleaseInfo {
  /// Version without the leading `v` (e.g. `1.3.0`).
  final String version;

  /// Release page on GitHub.
  final String pageUrl;

  /// Direct APK download, when the release has one attached.
  final String? apkUrl;

  /// Release notes (markdown, as GitHub returns them).
  final String notes;

  const ReleaseInfo({
    required this.version,
    required this.pageUrl,
    required this.notes,
    this.apkUrl,
  });
}

/// Raised when the check can't complete (no network, API error, bad payload).
/// [message] is user-facing Spanish.
class UpdateCheckException implements Exception {
  final String message;
  const UpdateCheckException(this.message);

  @override
  String toString() => 'UpdateCheckException: $message';
}

/// Parses a `MAJOR.MINOR.PATCH` string into its three numbers.
///
/// Tolerates a leading `v`, a `+build` suffix (Flutter's own version format)
/// and pre-release suffixes like `-beta.1`, which are ignored for ordering —
/// this project only ever tags plain releases. Missing components count as 0,
/// so `1.3` parses as `1.3.0`. Returns null if there is no leading number.
List<int>? parseVersion(String raw) {
  var s = raw.trim();
  if (s.startsWith('v') || s.startsWith('V')) s = s.substring(1);
  s = s.split('+').first.split('-').first;

  final parts = s.split('.');
  final numbers = <int>[];
  for (var i = 0; i < 3; i++) {
    if (i >= parts.length) {
      numbers.add(0);
      continue;
    }
    final n = int.tryParse(parts[i].trim());
    if (n == null) {
      // No leading number at all means this isn't a version string.
      if (i == 0) return null;
      numbers.add(0);
    } else {
      numbers.add(n);
    }
  }
  return numbers;
}

/// Returns a negative number if [a] is older than [b], 0 if equal, positive
/// if newer. Unparseable versions sort as older than anything parseable.
int compareVersions(String a, String b) {
  final va = parseVersion(a);
  final vb = parseVersion(b);
  if (va == null && vb == null) return 0;
  if (va == null) return -1;
  if (vb == null) return 1;
  for (var i = 0; i < 3; i++) {
    final diff = va[i] - vb[i];
    if (diff != 0) return diff;
  }
  return 0;
}

/// True when [latest] is strictly newer than [current].
bool isNewerVersion(String latest, String current) =>
    compareVersions(latest, current) > 0;

/// Extracts the fields we need from a GitHub `releases/latest` payload.
///
/// Throws [UpdateCheckException] if the JSON isn't shaped as expected.
ReleaseInfo parseLatestRelease(String body) {
  final Object? decoded;
  try {
    decoded = jsonDecode(body);
  } on FormatException {
    throw const UpdateCheckException('La respuesta del servidor no es válida.');
  }
  if (decoded is! Map<String, dynamic>) {
    throw const UpdateCheckException('La respuesta del servidor no es válida.');
  }

  final tag = decoded['tag_name'];
  if (tag is! String || tag.isEmpty) {
    throw const UpdateCheckException('La publicación no tiene versión.');
  }

  String? apkUrl;
  final assets = decoded['assets'];
  if (assets is List) {
    for (final asset in assets) {
      if (asset is Map<String, dynamic> &&
          asset['name'] is String &&
          (asset['name'] as String).toLowerCase().endsWith('.apk')) {
        final url = asset['browser_download_url'];
        if (url is String) {
          apkUrl = url;
          break;
        }
      }
    }
  }

  final version = tag.startsWith('v') ? tag.substring(1) : tag;
  final htmlUrl = decoded['html_url'];

  return ReleaseInfo(
    version: version,
    pageUrl: htmlUrl is String && htmlUrl.isNotEmpty
        ? htmlUrl
        : '$kRepoUrl/releases/latest',
    notes: decoded['body'] is String ? decoded['body'] as String : '',
    apkUrl: apkUrl,
  );
}

/// Queries the GitHub Releases API for the newest published release.
///
/// The whole feature is one unauthenticated GET; GitHub allows 60 per hour
/// per IP, and the silent check runs at most once a day.
class UpdateChecker {
  /// Injectable for tests: given a URL, returns the response body.
  final Future<String> Function(String url) fetch;

  UpdateChecker({Future<String> Function(String url)? fetch})
    : fetch = fetch ?? _httpGet;

  static Future<String> _httpGet(String url) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final request = await client.getUrl(Uri.parse(url));
      // GitHub rejects requests without a User-Agent.
      request.headers.set(HttpHeaders.userAgentHeader, 'PlayItMobile');
      request.headers.set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
      final response = await request.close().timeout(
        const Duration(seconds: 15),
      );

      if (response.statusCode == 404) {
        throw const UpdateCheckException(
          'El repositorio no tiene publicaciones todavía.',
        );
      }
      if (response.statusCode == 403) {
        throw const UpdateCheckException(
          'GitHub limitó las consultas. Inténtalo más tarde.',
        );
      }
      if (response.statusCode != 200) {
        throw UpdateCheckException(
          'GitHub respondió ${response.statusCode}.',
        );
      }
      return await response.transform(utf8.decoder).join();
    } on SocketException {
      throw const UpdateCheckException('Sin conexión a internet.');
    } on TimeoutException {
      throw const UpdateCheckException('La consulta tardó demasiado.');
    } on HandshakeException {
      throw const UpdateCheckException('No se pudo establecer la conexión.');
    } finally {
      client.close(force: true);
    }
  }

  /// Fetches the latest release and returns it only when it is newer than
  /// [currentVersion]; null means "already up to date".
  ///
  /// Network and parsing only — no storage — so it stays usable from tests
  /// without a Flutter binding. Throws [UpdateCheckException] on any failure,
  /// leaving the caller to surface it (manual check) or swallow it (silent).
  Future<ReleaseInfo?> checkForUpdate(String currentVersion) async {
    final release = parseLatestRelease(await fetch(_kLatestReleaseApi));
    return isNewerVersion(release.version, currentVersion) ? release : null;
  }

  /// Same as [checkForUpdate] but returns null instead of throwing, honours
  /// the user's auto-check preference, the once-a-day throttle, and the
  /// version the user chose to skip. For the silent check on startup.
  Future<ReleaseInfo?> checkForUpdateSilently(String currentVersion) async {
    final prefs = await SharedPreferences.getInstance();
    if (!(prefs.getBool(_prefAutoCheck) ?? true)) return null;

    final last = prefs.getInt(_prefLastCheck) ?? 0;
    final elapsed = DateTime.now().millisecondsSinceEpoch - last;
    if (elapsed < kAutoCheckInterval.inMilliseconds) return null;

    try {
      final release = await checkForUpdate(currentVersion);
      await markChecked();
      if (release == null) return null;
      if (prefs.getString(_prefSkippedVersion) == release.version) return null;
      return release;
    } on UpdateCheckException {
      // Offline or GitHub having a bad day: stay quiet, retry tomorrow.
      await markChecked();
      return null;
    }
  }

  /// Resets the once-a-day throttle. The manual check calls it too, so
  /// checking by hand also postpones the next automatic one.
  static Future<void> markChecked() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefLastCheck, DateTime.now().millisecondsSinceEpoch);
  }

  static Future<bool> autoCheckEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefAutoCheck) ?? true;
  }

  static Future<void> setAutoCheckEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefAutoCheck, value);
  }

  /// Silences the startup prompt for one specific version.
  static Future<void> skipVersion(String version) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefSkippedVersion, version);
  }
}
