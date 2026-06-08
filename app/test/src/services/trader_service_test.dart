import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lnmarkets_bot/services/log_service.dart';
import 'package:lnmarkets_bot/services/settings_service.dart';
import 'package:lnmarkets_bot/services/trader_service.dart';
import 'package:lnmarkets_bot/src/clients/fake_exchange_client.dart';
import 'package:lnmarkets_bot/src/clients/fake_market_data_client.dart';
import 'package:lnmarkets_bot/src/platform/macos/macos_bot_runtime_controller.dart';
import 'package:lnmarkets_bot/src/settings/credentials_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('start uses injected fake clients and does not call live APIs',
      () async {
    SharedPreferences.setMockInitialValues({
      'network': 'testnet',
      'check_interval': 5,
      'ema_fast': 3,
      'ema_slow': 5,
      'ema_signal': 8,
    });
    final settings =
        SettingsService(credentialsStore: MemoryCredentialsStore());
    await settings.load();
    final runtimeController = MacosBotRuntimeController();
    final log = LogService();
    final trader = TraderService(
      settings: settings,
      log: log,
      exchangeClient: FakeExchangeClient(balanceSats: 100000),
      marketDataClient: FakeMarketDataClient(),
      runtimeController: runtimeController,
    );

    await trader.start();

    expect(trader.running, isTrue);
    expect(trader.balance, 100000);
    expect(runtimeController.running, isTrue);
    expect(log.history.any((entry) => entry.message.contains('Conectado')),
        isTrue);

    trader.stop();
    expect(trader.running, isFalse);
    expect(runtimeController.running, isFalse);
    log.dispose();
  });

  test('fetchPriceOnce uses injected fake market data', () async {
    SharedPreferences.setMockInitialValues({});
    final settings =
        SettingsService(credentialsStore: MemoryCredentialsStore());
    await settings.load();
    final trader = TraderService(
      settings: settings,
      log: LogService(),
      exchangeClient: FakeExchangeClient(),
      marketDataClient: FakeMarketDataClient(basePrice: 42000),
      runtimeController: MacosBotRuntimeController(),
    );

    await trader.fetchPriceOnce();

    expect(trader.btcPrice, 42001);
    trader.dispose();
  });

  test('mock position storage key does not clear live position state',
      () async {
    SharedPreferences.setMockInitialValues({
      'bot_position':
          '{"id":"live-position","side":"long","entry_price":50000}',
      'mock_bot_position':
          '{"id":"mock-position","side":"long","entry_price":50000}',
      'ema_fast': 3,
      'ema_slow': 5,
      'ema_signal': 8,
    });
    final settings =
        SettingsService(credentialsStore: MemoryCredentialsStore());
    await settings.load();
    final trader = TraderService(
      settings: settings,
      log: LogService(),
      exchangeClient: FakeExchangeClient(),
      marketDataClient: FakeMarketDataClient(),
      runtimeController: MacosBotRuntimeController(),
      positionStorageKey: 'mock_bot_position',
    );

    await trader.start();
    trader.stop();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('bot_position'), contains('live-position'));
    expect(
        prefs.getString('mock_bot_position'), isNot(contains('live-position')));
  });

  test('start reconciles existing remote position instead of opening duplicate',
      () async {
    SharedPreferences.setMockInitialValues({
      'network': 'testnet',
      'check_interval': 5,
      'ema_fast': 3,
      'ema_slow': 5,
      'ema_signal': 8,
      'use_trailing_stop': false,
    });
    final settings =
        SettingsService(credentialsStore: MemoryCredentialsStore());
    await settings.load();
    final exchange = FakeExchangeClient(balanceSats: 100000);
    final remote = await exchange.openPosition('buy');
    final remoteId = remote['id'] as String;
    await exchange.setTakeProfit(remoteId, 51000);
    await exchange.setStopLoss(remoteId, 49000);
    final log = LogService();
    final trader = TraderService(
      settings: settings,
      log: log,
      exchangeClient: exchange,
      marketDataClient: FakeMarketDataClient(),
      runtimeController: MacosBotRuntimeController(),
    );

    await trader.start();

    final open = await exchange.getOpenPositions();
    expect(open, hasLength(1));
    expect(trader.position.id, remoteId);
    expect(trader.position.side, 'long');
    expect(trader.position.entryPrice, 50000);
    expect(trader.position.tpPrice, 51000);
    expect(trader.position.slPrice, 49000);
    expect(trader.stats.totalTrades, 0);

    trader.stop();
    log.dispose();
  });

  test('start replaces stale local position with existing remote position',
      () async {
    SharedPreferences.setMockInitialValues({
      'bot_position':
          '{"id":"stale-position","side":"long","entry_price":50000}',
      'network': 'testnet',
      'check_interval': 5,
      'ema_fast': 3,
      'ema_slow': 5,
      'ema_signal': 8,
    });
    final settings =
        SettingsService(credentialsStore: MemoryCredentialsStore());
    await settings.load();
    final exchange = FakeExchangeClient(balanceSats: 100000);
    final remote = await exchange.openPosition('buy');
    final remoteId = remote['id'] as String;
    final log = LogService();
    final trader = TraderService(
      settings: settings,
      log: log,
      exchangeClient: exchange,
      marketDataClient: FakeMarketDataClient(),
      runtimeController: MacosBotRuntimeController(),
    );

    await trader.start();

    final open = await exchange.getOpenPositions();
    final prefs = await SharedPreferences.getInstance();
    final savedPosition =
        jsonDecode(prefs.getString('bot_position')!) as Map<String, dynamic>;
    expect(open, hasLength(1));
    expect(trader.position.id, remoteId);
    expect(savedPosition['id'], remoteId);
    expect(trader.stats.totalTrades, 0);

    trader.stop();
    log.dispose();
  });
}
