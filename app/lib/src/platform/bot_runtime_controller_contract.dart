abstract class BotRuntimeController {
  bool get supportsPersistentBackground;

  void init();

  Future<void> start({
    required String title,
    required String text,
  });

  Future<void> update({
    required String title,
    required String text,
  });

  Future<void> stop();

  Future<void> requestBatteryOptimization();
}
