import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lnmarkets_bot/src/platform/bot_runtime_controller.dart';
import 'package:lnmarkets_bot/src/platform/desktop_bot_runtime_controller.dart';

void main() {
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  test('desktop runtime controller keeps explicit in-app runtime state',
      () async {
    final controller = DesktopBotRuntimeController();

    expect(controller.supportsPersistentBackground, isFalse);
    expect(controller.running, isFalse);
    expect(controller.lastTitle, isNull);
    expect(controller.lastText, isNull);

    await controller.start(
      title: 'LN Markets Bot',
      text: 'Running',
    );

    expect(controller.running, isTrue);
    expect(controller.lastTitle, 'LN Markets Bot');
    expect(controller.lastText, 'Running');

    await controller.update(
      title: 'LN Markets Bot',
      text: 'Still running',
    );

    expect(controller.running, isTrue);
    expect(controller.lastTitle, 'LN Markets Bot');
    expect(controller.lastText, 'Still running');

    await controller.stop();

    expect(controller.running, isFalse);
    expect(controller.lastTitle, isNull);
    expect(controller.lastText, isNull);
  });

  test('factory uses desktop runtime on Windows', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;

    expect(createBotRuntimeController(), isA<DesktopBotRuntimeController>());
  });
}
