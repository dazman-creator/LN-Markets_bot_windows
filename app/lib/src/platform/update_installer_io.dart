import 'dart:io';

import 'update_installer_contract.dart';

typedef UpdateProcessLauncher = Future<void> Function(
  String executable,
  List<String> arguments, {
  required ProcessStartMode mode,
  required bool runInShell,
});

typedef UpdateExit = void Function(int code);

UpdateInstaller createUpdateInstaller() => WindowsUpdateInstaller();

class WindowsUpdateInstaller implements UpdateInstaller {
  final UpdateProcessLauncher _launchProcess;
  final UpdateExit _exitApp;
  final Duration _exitDelay;

  WindowsUpdateInstaller({
    UpdateProcessLauncher? launchProcess,
    UpdateExit? exitApp,
    Duration exitDelay = const Duration(milliseconds: 300),
  })  : _launchProcess = launchProcess ?? _defaultLaunchProcess,
        _exitApp = exitApp ?? ((code) => exit(code)),
        _exitDelay = exitDelay;

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
    final staging = File(update.scriptPath).parent;
    final launcherPath = '${staging.path}\\launch_update.cmd';

    await File(launcherPath).writeAsString(
      _launcherScript(
        powershellPath: _powershellPath(),
        scriptPath: update.scriptPath,
        zipPath: update.zipPath,
        installRoot: root.path,
        currentPid: pid,
        exeName: exeName,
      ),
      flush: true,
    );

    await _launchProcess(
      'cmd.exe',
      ['/C', launcherPath],
      mode: ProcessStartMode.detached,
      runInShell: false,
    );

    await Future<void>.delayed(_exitDelay);
    _exitApp(0);
  }

  static Future<void> _defaultLaunchProcess(
    String executable,
    List<String> arguments, {
    required ProcessStartMode mode,
    required bool runInShell,
  }) async {
    await Process.start(
      executable,
      arguments,
      mode: mode,
      runInShell: runInShell,
    );
  }

  String _launcherScript({
    required String powershellPath,
    required String scriptPath,
    required String zipPath,
    required String installRoot,
    required int currentPid,
    required String exeName,
  }) =>
      '''
@echo off
setlocal
start "" /min ${_cmdQuote(powershellPath)} -NoProfile -ExecutionPolicy Bypass -File ${_cmdQuote(scriptPath)} -ZipPath ${_cmdQuote(zipPath)} -InstallRoot ${_cmdQuote(installRoot)} -CurrentPid $currentPid -ExeName ${_cmdQuote(exeName)}
''';

  String _powershellPath() {
    final systemRoot = Platform.environment['SystemRoot'];
    if (systemRoot != null && systemRoot.isNotEmpty) {
      final powershellPath =
          '$systemRoot\\System32\\WindowsPowerShell\\v1.0\\powershell.exe';
      if (File(powershellPath).existsSync()) return powershellPath;
    }
    return 'powershell.exe';
  }

  String _cmdQuote(String value) => '"${value.replaceAll('"', '""')}"';

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
$LogPath = Join-Path $Staging "install_update.log"

try {
  Start-Transcript -Path $LogPath -Append | Out-Null
} catch {
}

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

try {
  Stop-Transcript | Out-Null
} catch {
}
''';
}
