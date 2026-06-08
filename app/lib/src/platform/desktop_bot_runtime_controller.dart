import 'bot_runtime_controller_contract.dart';

class DesktopBotRuntimeController implements BotRuntimeController {
  bool _running = false;
  String? _lastTitle;
  String? _lastText;

  @override
  bool get supportsPersistentBackground => false;

  bool get running => _running;

  String? get lastTitle => _lastTitle;

  String? get lastText => _lastText;

  @override
  void init() {}

  @override
  Future<void> start({
    required String title,
    required String text,
  }) async {
    _running = true;
    _lastTitle = title;
    _lastText = text;
  }

  @override
  Future<void> update({
    required String title,
    required String text,
  }) async {
    _lastTitle = title;
    _lastText = text;
  }

  @override
  Future<void> stop() async {
    _running = false;
    _lastTitle = null;
    _lastText = null;
  }

  @override
  Future<void> requestBatteryOptimization() async {}
}
