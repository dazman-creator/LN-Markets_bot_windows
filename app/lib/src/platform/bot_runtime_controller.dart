import 'package:flutter/foundation.dart';

import '../../services/foreground_service.dart';
import 'bot_runtime_controller_contract.dart';
import 'desktop_bot_runtime_controller.dart';
import 'macos/macos_bot_runtime_controller.dart';

export 'bot_runtime_controller_contract.dart';

BotRuntimeController createBotRuntimeController() {
  if (kIsWeb) {
    return DesktopBotRuntimeController();
  }

  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
    case TargetPlatform.iOS:
      return ForegroundTaskBotRuntimeController();
    case TargetPlatform.macOS:
      return MacosBotRuntimeController();
    case TargetPlatform.windows:
    case TargetPlatform.linux:
    case TargetPlatform.fuchsia:
      return DesktopBotRuntimeController();
  }
}

class ForegroundTaskBotRuntimeController implements BotRuntimeController {
  @override
  bool get supportsPersistentBackground => true;

  @override
  void init() => ForegroundService.init();

  @override
  Future<void> start({
    required String title,
    required String text,
  }) =>
      ForegroundService.start(title: title, text: text);

  @override
  Future<void> update({
    required String title,
    required String text,
  }) =>
      ForegroundService.update(title: title, text: text);

  @override
  Future<void> stop() => ForegroundService.stop();

  @override
  Future<void> requestBatteryOptimization() =>
      ForegroundService.requestBatteryOptimization();
}
