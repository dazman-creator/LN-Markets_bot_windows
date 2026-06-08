import 'dart:io';

import 'update_installer_contract.dart';

UpdateInstaller createUpdateInstaller() => WindowsUpdateInstaller();

class WindowsUpdateInstaller implements UpdateInstaller {
  @override
  bool get isSupported => Platform.isWindows;

  @override
  Future<StagedUpdate> stage({
    required String tagName,
    required String zipFileName,
    required List<int> zipBytes,
  }) async {
    if (!isSupported) {
      throw UnsupportedError('Updates are only supported on Windows desktop.');
    }

    final root = _installRoot();
    final staging = Directory('${root.path}\\staging\\$tagName');
    if (staging.existsSync()) {
      await staging.delete(recursive: true);
    }
    await staging.create(recursive: true);

    final zipPath = '${staging.path}\\$zipFileName';
    await File(zipPath).writeAsBytes(zipBytes, flush: true);

    final scriptPath = '${staging.path}\\install_update.ps1';
    await File(scriptPath).writeAsString(_installScript(), flush: true);

    return StagedUpdate(
      tagName: tagName,
      zipPath: zipPath,
      scriptPath: scriptPath,
    );
  }

  @override
  Future<void> installAndRestart(StagedUpdate update) async {
    if (!isSupported) {
      throw UnsupportedError('Updates are only supported on Windows desktop.');
    }

    final root = _installRoot();
    final exeName =
        Platform.resolvedExecutable.split(Platform.pathSeparator).last;
    final args = [
      '-NoProfile',
      '-ExecutionPolicy',
      'Bypass',
      '-File',
      update.scriptPath,
      '-ZipPath',
      update.zipPath,
      '-InstallRoot',
      root.path,
      '-CurrentPid',
      pid.toString(),
      '-ExeName',
      exeName,
    ];

    await Process.start(
      'powershell.exe',
      args,
      mode: ProcessStartMode.detached,
      runInShell: false,
    );

    await Future<void>.delayed(const Duration(milliseconds: 300));
    exit(0);
  }

  Directory _installRoot() {
    final localAppData = Platform.environment['LOCALAPPDATA'];
    if (localAppData == null || localAppData.isEmpty) {
      throw StateError('LOCALAPPDATA is not defined.');
    }
    return Directory('$localAppData\\LNMarketsBot');
  }

  String _installScript() => r'''
param(
  [Parameter(Mandatory=$true)][string]$ZipPath,
  [Parameter(Mandatory=$true)][string]$InstallRoot,
  [Parameter(Mandatory=$true)][int]$CurrentPid,
  [Parameter(Mandatory=$true)][string]$ExeName
)

$ErrorActionPreference = "Stop"

$Current = Join-Path $InstallRoot "current"
$Previous = Join-Path $InstallRoot "previous"
$Staging = Split-Path -Parent $ZipPath
$Extract = Join-Path $Staging "extract"

try {
  Wait-Process -Id $CurrentPid -Timeout 90 -ErrorAction SilentlyContinue
} catch {
}

Start-Sleep -Milliseconds 700

if (Test-Path $Extract) {
  Remove-Item -LiteralPath $Extract -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $Extract | Out-Null
Expand-Archive -LiteralPath $ZipPath -DestinationPath $Extract -Force

$Exe = Get-ChildItem -LiteralPath $Extract -Recurse -Filter $ExeName |
  Select-Object -First 1
if (-not $Exe) {
  throw "Executable $ExeName not found in update package."
}

$Payload = Split-Path -Parent $Exe.FullName
New-Item -ItemType Directory -Force -Path $InstallRoot | Out-Null

if (Test-Path $Previous) {
  Remove-Item -LiteralPath $Previous -Recurse -Force
}

if (Test-Path $Current) {
  Move-Item -LiteralPath $Current -Destination $Previous -Force
}

New-Item -ItemType Directory -Force -Path $Current | Out-Null
Copy-Item -Path (Join-Path $Payload "*") -Destination $Current -Recurse -Force

$NewExe = Join-Path $Current $ExeName
Start-Process -FilePath $NewExe -WorkingDirectory $Current
''';
}
