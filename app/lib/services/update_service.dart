import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import '../app_version.dart';
import '../src/platform/update_installer_contract.dart';
import '../src/platform/update_installer_factory.dart';

class UpdateRelease {
  final String tagName;
  final ReleaseVersion version;
  final String htmlUrl;
  final String zipName;
  final Uri zipUrl;
  final Uri sha256Url;
  final bool prerelease;

  const UpdateRelease({
    required this.tagName,
    required this.version,
    required this.htmlUrl,
    required this.zipName,
    required this.zipUrl,
    required this.sha256Url,
    required this.prerelease,
  });
}

class ReleaseVersion implements Comparable<ReleaseVersion> {
  final int major;
  final int minor;
  final int patch;

  const ReleaseVersion(this.major, this.minor, this.patch);

  static ReleaseVersion? parse(String value) {
    final normalized = value.trim().replaceFirst(RegExp(r'^[vV]'), '');
    final core = normalized.split(RegExp(r'[-+]')).first;
    final parts = core.split('.');
    if (parts.length < 3) return null;
    final major = int.tryParse(parts[0]);
    final minor = int.tryParse(parts[1]);
    final patch = int.tryParse(parts[2]);
    if (major == null || minor == null || patch == null) return null;
    return ReleaseVersion(major, minor, patch);
  }

  @override
  int compareTo(ReleaseVersion other) {
    if (major != other.major) return major.compareTo(other.major);
    if (minor != other.minor) return minor.compareTo(other.minor);
    return patch.compareTo(other.patch);
  }

  @override
  String toString() => '$major.$minor.$patch';
}

class UpdateException implements Exception {
  final String message;

  const UpdateException(this.message);

  @override
  String toString() => message;
}

class UpdateService {
  static const owner = 'dazman-creator';
  static const repo = 'LN-Markets_bot_windows';
  static const includePrereleases = true;
  static const _githubApiHeaders = {
    'Accept': 'application/vnd.github+json',
    'User-Agent': 'LN-Markets-Bot-Windows-Updater',
  };
  static const _assetDownloadHeaders = {
    'Accept': 'application/octet-stream',
    'User-Agent': 'LN-Markets-Bot-Windows-Updater',
  };

  final http.Client _client;
  final bool _ownsClient;
  final UpdateInstaller _installer;
  final ReleaseVersion _currentVersion;
  final Duration _downloadRetryDelay;

  UpdateService({
    http.Client? client,
    UpdateInstaller? installer,
    ReleaseVersion? currentVersion,
    Duration downloadRetryDelay = const Duration(seconds: 1),
  })  : _client = client ?? http.Client(),
        _ownsClient = client == null,
        _installer = installer ?? createUpdateInstaller(),
        _currentVersion =
            currentVersion ?? ReleaseVersion.parse(AppVersion.version)!,
        _downloadRetryDelay = downloadRetryDelay;

  bool get isSupported => _installer.isSupported;

  Future<UpdateRelease?> findLatestAvailable() async {
    if (!isSupported) return null;

    final response = await _client.get(
      Uri.https('api.github.com', '/repos/$owner/$repo/releases'),
      headers: _githubApiHeaders,
    );

    if (response.statusCode != 200) {
      throw UpdateException('GitHub releases returned ${response.statusCode}.');
    }

    final releases = jsonDecode(response.body) as List<dynamic>;
    final candidates = <UpdateRelease>[];
    for (final item in releases) {
      final parsed = _parseRelease(item as Map<String, dynamic>);
      if (parsed != null && parsed.version.compareTo(_currentVersion) > 0) {
        candidates.add(parsed);
      }
    }

    candidates.sort((a, b) => b.version.compareTo(a.version));
    return candidates.isEmpty ? null : candidates.first;
  }

  Future<StagedUpdate> downloadAndStage(UpdateRelease release) async {
    final shaResponse = await _downloadAssetWithRetry(release.sha256Url);
    if (shaResponse.statusCode != 200) {
      throw UpdateException(
          'Could not download SHA256 file (${shaResponse.statusCode}).');
    }
    final expectedHash = _extractSha256(shaResponse.body);
    if (expectedHash == null) {
      throw const UpdateException('SHA256 file is invalid.');
    }

    final zipResponse = await _downloadAssetWithRetry(release.zipUrl);
    if (zipResponse.statusCode != 200) {
      throw UpdateException(
          'Could not download update package (${zipResponse.statusCode}).');
    }

    final actualHash = sha256.convert(zipResponse.bodyBytes).toString();
    if (actualHash.toLowerCase() != expectedHash.toLowerCase()) {
      throw const UpdateException('Update package hash does not match.');
    }

    return _installer.stage(
      tagName: release.tagName,
      zipFileName: release.zipName,
      zipBytes: zipResponse.bodyBytes,
    );
  }

  Future<void> installAndRestart(StagedUpdate update) =>
      _installer.installAndRestart(update);

  Future<http.Response> _downloadAssetWithRetry(Uri url) async {
    http.Response? response;
    for (var attempt = 1; attempt <= 3; attempt++) {
      response = await _client.get(url, headers: _assetDownloadHeaders);
      if (response.statusCode < 500) return response;
      if (attempt < 3 && _downloadRetryDelay > Duration.zero) {
        await Future<void>.delayed(Duration(
          milliseconds: _downloadRetryDelay.inMilliseconds * attempt,
        ));
      }
    }
    return response!;
  }

  void dispose() {
    if (_ownsClient) _client.close();
  }

  UpdateRelease? _parseRelease(Map<String, dynamic> release) {
    if (release['draft'] == true) return null;
    final isPrerelease = release['prerelease'] == true;
    if (isPrerelease && !includePrereleases) return null;

    final tagName = release['tag_name'] as String?;
    final version = tagName == null ? null : ReleaseVersion.parse(tagName);
    if (tagName == null || version == null) return null;

    final assets = (release['assets'] as List<dynamic>?)
            ?.whereType<Map<String, dynamic>>()
            .toList() ??
        const [];
    final zip = _findAsset(assets, (name) {
      final lower = name.toLowerCase();
      return lower.endsWith('.zip') && lower.contains('windows');
    });
    final sha =
        _findAsset(assets, (name) => name.toLowerCase().endsWith('.sha256'));
    if (zip == null || sha == null) return null;

    final zipUrl =
        zip['url'] as String? ?? zip['browser_download_url'] as String?;
    final shaUrl =
        sha['url'] as String? ?? sha['browser_download_url'] as String?;
    if (zipUrl == null || shaUrl == null) return null;

    return UpdateRelease(
      tagName: tagName,
      version: version,
      htmlUrl: release['html_url'] as String? ?? '',
      zipName: zip['name'] as String,
      zipUrl: Uri.parse(zipUrl),
      sha256Url: Uri.parse(shaUrl),
      prerelease: isPrerelease,
    );
  }

  Map<String, dynamic>? _findAsset(
    List<Map<String, dynamic>> assets,
    bool Function(String name) predicate,
  ) {
    for (final asset in assets) {
      final name = asset['name'] as String?;
      if (name != null && predicate(name)) return asset;
    }
    return null;
  }

  String? _extractSha256(String content) {
    final match = RegExp(r'\b[a-fA-F0-9]{64}\b').firstMatch(content);
    return match?.group(0);
  }
}
