import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lnmarkets_bot/src/platform/update_installer_contract.dart';
import 'package:lnmarkets_bot/src/platform/update_installer_io.dart';

class CapturedLaunch {
  final String executable;
  final List<String> arguments;
  final ProcessStartMode mode;
  final bool runInShell;

  const CapturedLaunch({
    required this.executable,
    required this.arguments,
    required this.mode,
    required this.runInShell,
  });
}

void main() {
  test('installAndRestart launches updater through detached cmd helper',
      () async {
    if (!Platform.isWindows) return;

    final staging = await Directory.systemTemp.createTemp('lnbot-updater-');
    addTearDown(() async {
      if (staging.existsSync()) {
        await staging.delete(recursive: true);
      }
    });

    final script = File('${staging.path}\\install_update.ps1');
    final zip = File('${staging.path}\\LN-Markets-Bot-Windows-v9.9.9.zip');
    await script.writeAsString('Write-Output "ok"');
    await zip.writeAsBytes([1, 2, 3]);

    final launches = <CapturedLaunch>[];
    int? exitCode;
    final installer = WindowsUpdateInstaller(
      launchProcess: (
        executable,
        arguments, {
        required mode,
        required runInShell,
      }) async {
        launches.add(
          CapturedLaunch(
            executable: executable,
            arguments: arguments,
            mode: mode,
            runInShell: runInShell,
          ),
        );
      },
      exitApp: (code) => exitCode = code,
      exitDelay: Duration.zero,
    );

    await installer.installAndRestart(
      StagedUpdate(
        tagName: 'v9.9.9',
        zipPath: zip.path,
        scriptPath: script.path,
      ),
    );

    final launcher = File('${staging.path}\\launch_update.cmd');
    expect(await launcher.exists(), isTrue);
    final launcherContent = await launcher.readAsString();
    expect(launcherContent, contains('@echo off'));
    expect(launcherContent, contains('start "" /min'));
    expect(launcherContent, contains('-ExecutionPolicy Bypass'));
    expect(launcherContent, contains(script.path));
    expect(launcherContent, contains(zip.path));
    expect(launcherContent, contains('-InstallRoot'));
    expect(launcherContent, contains('-CurrentPid'));
    expect(launcherContent, contains('-ExeName'));

    expect(launches, hasLength(1));
    expect(launches.single.executable, 'cmd.exe');
    expect(launches.single.arguments, ['/C', launcher.path]);
    expect(launches.single.mode, ProcessStartMode.detached);
    expect(launches.single.runInShell, isFalse);
    expect(exitCode, 0);
  });
}
