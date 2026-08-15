import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:playit_mobile/services/update_checker.dart';

void main() {
  group('parseVersion', () {
    test('parses a plain semver string', () {
      expect(parseVersion('1.3.0'), [1, 3, 0]);
    });

    test('tolerates the leading v of a git tag', () {
      expect(parseVersion('v1.3.0'), [1, 3, 0]);
      expect(parseVersion('V2.0.1'), [2, 0, 1]);
    });

    test('drops the +build suffix of the Flutter version format', () {
      expect(parseVersion('1.3.0+7'), [1, 3, 0]);
    });

    test('drops pre-release suffixes', () {
      expect(parseVersion('1.4.0-beta.2'), [1, 4, 0]);
    });

    test('pads missing components with zeros', () {
      expect(parseVersion('1.3'), [1, 3, 0]);
      expect(parseVersion('2'), [2, 0, 0]);
    });

    test('returns null when there is no leading number', () {
      expect(parseVersion('nightly'), isNull);
      expect(parseVersion(''), isNull);
    });
  });

  group('compareVersions', () {
    test('orders by major, then minor, then patch', () {
      expect(compareVersions('2.0.0', '1.9.9'), greaterThan(0));
      expect(compareVersions('1.3.0', '1.2.9'), greaterThan(0));
      expect(compareVersions('1.3.1', '1.3.0'), greaterThan(0));
      expect(compareVersions('1.3.0', '1.3.0'), 0);
      expect(compareVersions('1.2.9', '1.3.0'), lessThan(0));
    });

    test('does not compare components as strings', () {
      // The bug this guards: '10' < '9' lexicographically.
      expect(compareVersions('1.10.0', '1.9.0'), greaterThan(0));
    });

    test('unparseable versions sort below parseable ones', () {
      expect(compareVersions('nightly', '1.0.0'), lessThan(0));
      expect(compareVersions('1.0.0', 'nightly'), greaterThan(0));
      expect(compareVersions('nightly', 'nightly'), 0);
    });
  });

  group('isNewerVersion', () {
    test('is strict: the same version is not an update', () {
      expect(isNewerVersion('1.3.0', '1.3.0'), isFalse);
    });

    test('ignores the build suffix of the installed version', () {
      expect(isNewerVersion('1.3.0', '1.3.0+9'), isFalse);
      expect(isNewerVersion('1.4.0', '1.3.0+9'), isTrue);
    });

    test('a downgrade is not an update', () {
      expect(isNewerVersion('1.2.0', '1.3.0'), isFalse);
    });
  });

  group('parseLatestRelease', () {
    String release({
      String tag = 'v1.4.0',
      String body = 'Notas',
      List<Map<String, String>> assets = const [],
    }) => jsonEncode({
      'tag_name': tag,
      'html_url': 'https://github.com/RavilesX/playit_mobile/releases/tag/$tag',
      'body': body,
      'assets': assets,
    });

    test('strips the leading v from the tag', () {
      expect(parseLatestRelease(release()).version, '1.4.0');
    });

    test('picks the APK asset download URL', () {
      final info = parseLatestRelease(
        release(
          assets: [
            {
              'name': 'app-release.aab',
              'browser_download_url': 'https://example.invalid/a.aab',
            },
            {
              'name': 'app-release.apk',
              'browser_download_url': 'https://example.invalid/a.apk',
            },
          ],
        ),
      );
      expect(info.apkUrl, 'https://example.invalid/a.apk');
    });

    test('apkUrl is null when the release has no APK attached', () {
      expect(parseLatestRelease(release()).apkUrl, isNull);
    });

    test('falls back to the releases page when html_url is missing', () {
      final info = parseLatestRelease(
        jsonEncode({'tag_name': 'v1.4.0', 'body': ''}),
      );
      expect(info.pageUrl, '$kRepoUrl/releases/latest');
    });

    test('keeps the release notes', () {
      expect(parseLatestRelease(release(body: 'Arregla X')).notes, 'Arregla X');
    });

    test('throws on malformed JSON', () {
      expect(
        () => parseLatestRelease('<html>404</html>'),
        throwsA(isA<UpdateCheckException>()),
      );
    });

    test('throws when the payload has no tag', () {
      expect(
        () => parseLatestRelease(jsonEncode({'body': 'sin tag'})),
        throwsA(isA<UpdateCheckException>()),
      );
    });
  });

  group('UpdateChecker.checkForUpdate', () {
    test('returns the release when the tag is newer', () async {
      final checker = UpdateChecker(
        fetch: (_) async => jsonEncode({
          'tag_name': 'v2.0.0',
          'html_url': 'https://example.invalid/r',
          'body': '',
          'assets': const [],
        }),
      );
      final release = await checker.checkForUpdate('1.3.0');
      expect(release?.version, '2.0.0');
    });

    test('returns null when the installed version is current', () async {
      final checker = UpdateChecker(
        fetch: (_) async => jsonEncode({
          'tag_name': 'v1.3.0',
          'html_url': 'https://example.invalid/r',
          'body': '',
          'assets': const [],
        }),
      );
      expect(await checker.checkForUpdate('1.3.0'), isNull);
    });

    test('propagates fetch failures as UpdateCheckException', () async {
      final checker = UpdateChecker(
        fetch: (_) async => throw const UpdateCheckException('Sin conexión.'),
      );
      expect(
        () => checker.checkForUpdate('1.3.0'),
        throwsA(isA<UpdateCheckException>()),
      );
    });
  });
}
