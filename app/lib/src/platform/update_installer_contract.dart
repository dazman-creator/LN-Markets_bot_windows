class StagedUpdate {
  final String tagName;
  final String zipPath;
  final String scriptPath;

  const StagedUpdate({
    required this.tagName,
    required this.zipPath,
    required this.scriptPath,
  });
}

abstract class UpdateInstaller {
  bool get isSupported;

  Future<StagedUpdate> stage({
    required String tagName,
    required String zipFileName,
    required List<int> zipBytes,
  });

  Future<void> installAndRestart(StagedUpdate update);
}
