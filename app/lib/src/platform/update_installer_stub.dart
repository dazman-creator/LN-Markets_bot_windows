import 'update_installer_contract.dart';

UpdateInstaller createUpdateInstaller() => const UnsupportedUpdateInstaller();

class UnsupportedUpdateInstaller implements UpdateInstaller {
  const UnsupportedUpdateInstaller();

  @override
  bool get isSupported => false;

  @override
  Future<StagedUpdate> stage({
    required String tagName,
    required String zipFileName,
    required List<int> zipBytes,
  }) {
    throw UnsupportedError('Updates are only supported on Windows desktop.');
  }

  @override
  Future<void> installAndRestart(StagedUpdate update) {
    throw UnsupportedError('Updates are only supported on Windows desktop.');
  }
}
