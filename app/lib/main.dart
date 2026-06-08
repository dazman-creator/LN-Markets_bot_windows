import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_theme.dart';
import 'i18n.dart';
import 'services/settings_service.dart';
import 'services/trader_service.dart';
import 'services/log_service.dart';
import 'services/remote_config_service.dart';
import 'src/clients/fake_exchange_client.dart';
import 'src/clients/fake_market_data_client.dart';
import 'src/platform/desktop_bot_runtime_controller.dart';
import 'src/platform/bot_runtime_controller.dart';
import 'src/settings/credentials_store.dart';
import 'screens/splash_screen.dart';
import 'screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS)) {
    await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  }

  const mockMode = bool.fromEnvironment('LNMBOT_MOCK_MODE');
  if (mockMode) {
    runApp(await buildMockSafeApp());
    return;
  }

  runApp(await buildLiveApp());
}

Future<LNMarketsApp> buildLiveApp() async {
  final runtimeController = createBotRuntimeController();
  runtimeController.init();

  final settings = SettingsService();
  await settings.load();
  AppLocalizations.setLanguage(settings.language);

  final logService = LogService();
  final traderService = TraderService(
    settings: settings,
    log: logService,
    runtimeController: runtimeController,
  );

  // Fetch remote exchange config (non-blocking, cached for offline use)
  RemoteConfigService.init();

  return LNMarketsApp(
    settings: settings,
    traderService: traderService,
    logService: logService,
    runtimeController: runtimeController,
  );
}

Future<LNMarketsApp> buildMockSafeApp() async {
  final runtimeController = DesktopBotRuntimeController();
  runtimeController.init();

  final settings = SettingsService(credentialsStore: MemoryCredentialsStore());
  await settings.load();
  AppLocalizations.setLanguage(settings.language);

  final logService = LogService();
  final traderService = TraderService(
    settings: settings,
    log: logService,
    exchangeClient: FakeExchangeClient(balanceSats: 100000),
    marketDataClient: FakeMarketDataClient(),
    runtimeController: runtimeController,
    positionStorageKey: 'mock_bot_position',
  );

  return LNMarketsApp(
    settings: settings,
    traderService: traderService,
    logService: logService,
    runtimeController: runtimeController,
    initialSplashDone: true,
    showSponsorBanner: false,
    enableExternalEffects: false,
  );
}

class LNMarketsApp extends StatefulWidget {
  final SettingsService settings;
  final TraderService traderService;
  final LogService logService;
  final BotRuntimeController runtimeController;
  final bool initialSplashDone;
  final bool showSponsorBanner;
  final bool enableExternalEffects;

  const LNMarketsApp({
    super.key,
    required this.settings,
    required this.traderService,
    required this.logService,
    required this.runtimeController,
    this.initialSplashDone = false,
    this.showSponsorBanner = true,
    this.enableExternalEffects = true,
  });

  @override
  State<LNMarketsApp> createState() => _LNMarketsAppState();
}

class _LNMarketsAppState extends State<LNMarketsApp> {
  late bool _splashDone;

  @override
  void initState() {
    super.initState();
    _splashDone = widget.initialSplashDone;
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LN Markets Bot',
      theme: AppTheme.dark,
      debugShowCheckedModeBanner: false,
      home: _splashDone
          ? HomeScreen(
              settings: widget.settings,
              traderService: widget.traderService,
              logService: widget.logService,
              runtimeController: widget.runtimeController,
              showSponsorBanner: widget.showSponsorBanner,
              enableExternalEffects: widget.enableExternalEffects,
            )
          : SplashScreen(
              onDone: () => setState(() => _splashDone = true),
            ),
    );
  }
}
