import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lnmarkets_bot/services/update_service.dart';
import 'package:lnmarkets_bot/src/platform/update_installer_contract.dart';

void main() {
  test('findLatestAvailable selects newer prerelease with Windows assets',
      () async {
    final service = UpdateService(
      client: MockClient((request) async {
        expect(request.url.path,
            '/repos/dazman-creator/LN-Markets_bot_windows/releases');
        return http.Response(
            jsonEncode([
              _release('v3.3.2', prerelease: true),
              _release('v3.3.1', prerelease: true),
            ]),
            200);
      }),
      installer: const _FakeInstaller(),
      currentVersion: const ReleaseVersion(3, 3, 1),
    );

    final release = await service.findLatestAvailable();

    expect(release, isNotNull);
    expect(release!.tagName, 'v3.3.2');
    expect(release.prerelease, isTrue);
  });

  test('findLatestAvailable ignores same or older versions', () async {
    final service = UpdateService(
      client: MockClient((request) async {
        return http.Response(
            jsonEncode([
              _release('v3.3.1', prerelease: true),
              _release('v3.3.0', prerelease: false),
            ]),
            200);
      }),
      installer: const _FakeInstaller(),
      currentVersion: const ReleaseVersion(3, 3, 1),
    );

    expect(await service.findLatestAvailable(), isNull);
  });

  test('downloadAndStage validates sha256 before staging', () async {
    final bytes = utf8.encode('zip-bytes');
    const expectedHash = '4b9a4ac59f3c3aa32273260df6cf4bf'
        '358d1c46f8415126aa35b6380d0abb8f7';
    const installer = _FakeInstaller();
    final service = UpdateService(
      client: MockClient((request) async {
        if (request.url.path.endsWith('.sha256')) {
          return http.Response('$expectedHash  update.zip', 200);
        }
        return http.Response.bytes(bytes, 200);
      }),
      installer: installer,
      currentVersion: const ReleaseVersion(3, 3, 1),
    );

    final staged = await service.downloadAndStage(UpdateRelease(
      tagName: 'v3.3.2',
      version: const ReleaseVersion(3, 3, 2),
      htmlUrl: 'https://github.com/release',
      zipName: 'LN-Markets-Bot-Windows-v3.3.2.zip',
      zipUrl: Uri.parse('https://example.com/update.zip'),
      sha256Url: Uri.parse('https://example.com/update.zip.sha256'),
      prerelease: true,
    ));

    expect(staged.tagName, 'v3.3.2');
    expect(installer.stagedBytes, bytes);
  });
}

Map<String, Object?> _release(String tagName, {required bool prerelease}) => {
      'tag_name': tagName,
      'draft': false,
      'prerelease': prerelease,
      'html_url': 'https://github.com/release/$tagName',
      'assets': [
        {
          'name': 'LN-Markets-Bot-Windows-$tagName.zip',
          'browser_download_url': 'https://example.com/$tagName.zip',
        },
        {
          'name': 'LN-Markets-Bot-Windows-$tagName.zip.sha256',
          'browser_download_url': 'https://example.com/$tagName.zip.sha256',
        },
      ],
    };

class _FakeInstaller implements UpdateInstaller {
  const _FakeInstaller();

  static List<int>? _stagedBytes;

  List<int>? get stagedBytes => _stagedBytes;

  @override
  bool get isSupported => true;

  @override
  Future<StagedUpdate> stage({
    required String tagName,
    required String zipFileName,
    required List<int> zipBytes,
  }) async {
    _stagedBytes = zipBytes;
    return StagedUpdate(
      tagName: tagName,
      zipPath: zipFileName,
      scriptPath: 'install_update.ps1',
    );
  }

  @override
  Future<void> installAndRestart(StagedUpdate update) async {}
}
