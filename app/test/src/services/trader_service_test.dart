import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lnmarkets_bot/services/binance_api.dart';
import 'package:lnmarkets_bot/services/log_service.dart';
import 'package:lnmarkets_bot/services/settings_service.dart';
import 'package:lnmarkets_bot/services/trader_service.dart';
import 'package:lnmarkets_bot/src/clients/fake_exchange_client.dart';
import 'package:lnmarkets_bot/src/clients/fake_market_data_client.dart';
import 'package:lnmarkets_bot/src/clients/market_data_client.dart';
import 'package:lnmarkets_bot/src/platform/macos/macos_bot_runtime_controller.dart';
import 'package:lnmarkets_bot/src/settings/credentials_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FailingTpSlExchangeClient extends FakeExchangeClient {
  FailingTpSlExchangeClient({super.balanceSats});

  @override
  Future<void> applyTpSl(String id, String side, double entryPrice) async {
    throw Exception('protect failed');
  }
}

class FailingStopLossExchangeClient extends FakeExchangeClient {
  FailingStopLossExchangeClient({super.balanceSats});

  @override
  Future<void> setStopLoss(String id, double price) async {
    throw Exception('stop loss failed');
  }
}

class BlockingCycleMarketDataClient implements MarketDataClient {
  int fetchCalls = 0;
  final secondCycleStarted = Completer<void>();
  final releaseSecondCycle = Completer<void>();

  @override
  Future<List<Candle>> fetchCandles(String interval, int limit) async {
    fetchCalls++;
    if (fetchCalls == 2) {
      secondCycleStarted.complete();
      await releaseSecondCycle.future;
    }
    final safeLimit = limit < 1 ? 1 : limit;
    return List.generate(
      safeLimit,
      (_) => const Candle(49999, 50001, 49998, 50000, 100),
    );
  }

  @override
  Future<double> fetchPrice() async => 50000;
}

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

  test('start closes new position and stops when TP/SL protection fails',
      () async {
    SharedPreferences.setMockInitialValues({
      'network': 'testnet',
      'check_interval': 5,
      'ema_fast': 3,
      'ema_slow': 5,
      'ema_signal': 8,
      'use_trailing_stop': false,
      'take_profit_pct': 1.0,
      'stop_loss_pct': 1.0,
    });
    final settings =
        SettingsService(credentialsStore: MemoryCredentialsStore());
    await settings.load();
    final exchange = FailingTpSlExchangeClient(balanceSats: 100000);
    final runtimeController = MacosBotRuntimeController();
    final log = LogService();
    final trader = TraderService(
      settings: settings,
      log: log,
      exchangeClient: exchange,
      marketDataClient: FakeMarketDataClient(),
      runtimeController: runtimeController,
    );

    await trader.start();

    final open = await exchange.getOpenPositions();
    final prefs = await SharedPreferences.getInstance();
    expect(open, isEmpty);
    expect(trader.running, isFalse);
    expect(runtimeController.running, isFalse);
    expect(trader.position.hasPosition, isFalse);
    expect(prefs.getString('bot_position'), isNull);
    expect(
      log.history
          .any((entry) => entry.message.contains('Fechando defensivamente')),
      isTrue,
    );

    log.dispose();
  });

  test('start closes new position and stops when trailing stop fails',
      () async {
    SharedPreferences.setMockInitialValues({
      'network': 'testnet',
      'check_interval': 5,
      'ema_fast': 3,
      'ema_slow': 5,
      'ema_signal': 8,
      'use_trailing_stop': true,
      'trailing_stop_pct': 1.0,
    });
    final settings =
        SettingsService(credentialsStore: MemoryCredentialsStore());
    await settings.load();
    final exchange = FailingStopLossExchangeClient(balanceSats: 100000);
    final runtimeController = MacosBotRuntimeController();
    final log = LogService();
    final trader = TraderService(
      settings: settings,
      log: log,
      exchangeClient: exchange,
      marketDataClient: FakeMarketDataClient(),
      runtimeController: runtimeController,
    );

    await trader.start();

    final open = await exchange.getOpenPositions();
    final prefs = await SharedPreferences.getInstance();
    expect(open, isEmpty);
    expect(trader.running, isFalse);
    expect(runtimeController.running, isFalse);
    expect(trader.position.hasPosition, isFalse);
    expect(prefs.getString('bot_position'), isNull);
    expect(
      log.history
          .any((entry) => entry.message.contains('Fechando defensivamente')),
      isTrue,
    );

    log.dispose();
  });

  test('periodic cycle skips when previous cycle is still running', () async {
    SharedPreferences.setMockInitialValues({
      'network': 'testnet',
      'check_interval': 0,
      'ema_fast': 3,
      'ema_slow': 5,
      'ema_signal': 8,
      'use_trailing_stop': false,
    });
    final settings =
        SettingsService(credentialsStore: MemoryCredentialsStore());
    await settings.load();
    final marketData = BlockingCycleMarketDataClient();
    final log = LogService();
    final trader = TraderService(
      settings: settings,
      log: log,
      exchangeClient: FakeExchangeClient(balanceSats: 100000),
      marketDataClient: marketData,
      runtimeController: MacosBotRuntimeController(),
    );

    await trader.start();
    expect(marketData.fetchCalls, 1);

    await marketData.secondCycleStarted.future
        .timeout(const Duration(seconds: 2));
    for (var i = 0; i < 20; i++) {
      if (log.history
          .any((entry) => entry.message.contains('Pulando ciclo sobreposto'))) {
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }

    expect(marketData.fetchCalls, 2);
    expect(
      log.history
          .any((entry) => entry.message.contains('Pulando ciclo sobreposto')),
      isTrue,
    );

    trader.stop();
    marketData.releaseSecondCycle.complete();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    log.dispose();
  });
}
