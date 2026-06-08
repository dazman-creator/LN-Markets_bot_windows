import 'package:flutter_test/flutter_test.dart';
import 'package:lnmarkets_bot/services/settings_service.dart';
import 'package:lnmarkets_bot/src/settings/credentials_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('defaults to testnet when no network preference exists', () async {
    SharedPreferences.setMockInitialValues({});
    final service = SettingsService(credentialsStore: MemoryCredentialsStore());

    await service.load();

    expect(service.network, 'testnet');
    expect(service.baseUrl, 'https://api.testnet4.lnmarkets.com');
  });

  test('load migrates legacy plaintext credentials and removes them from prefs',
      () async {
    SharedPreferences.setMockInitialValues({
      'api_key': 'legacy-key',
      'api_secret': 'legacy-secret',
      'api_passphrase': 'legacy-passphrase',
      'network': 'testnet',
    });
    final credentialsStore = MemoryCredentialsStore();
    final service = SettingsService(credentialsStore: credentialsStore);

    await service.load();

    expect(service.apiKey, 'legacy-key');
    expect(service.apiSecret, 'legacy-secret');
    expect(service.apiPassphrase, 'legacy-passphrase');
    expect(await credentialsStore.read('api_key'), 'legacy-key');
    expect(await credentialsStore.read('api_secret'), 'legacy-secret');
    expect(await credentialsStore.read('api_passphrase'), 'legacy-passphrase');

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('api_key'), isNull);
    expect(prefs.getString('api_secret'), isNull);
    expect(prefs.getString('api_passphrase'), isNull);
    expect(prefs.getString('network'), 'testnet');
  });

  test(
      'load removes legacy plaintext credentials even when secure values exist',
      () async {
    SharedPreferences.setMockInitialValues({
      'api_key': 'legacy-key',
      'api_secret': 'legacy-secret',
      'api_passphrase': 'legacy-passphrase',
    });
    final credentialsStore = MemoryCredentialsStore({
      'api_key': 'secure-key',
      'api_secret': 'secure-secret',
      'api_passphrase': 'secure-passphrase',
    });
    final service = SettingsService(credentialsStore: credentialsStore);

    await service.load();

    expect(service.apiKey, 'secure-key');
    expect(service.apiSecret, 'secure-secret');
    expect(service.apiPassphrase, 'secure-passphrase');

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('api_key'), isNull);
    expect(prefs.getString('api_secret'), isNull);
    expect(prefs.getString('api_passphrase'), isNull);
  });

  test('save removes any legacy plaintext credential values from prefs',
      () async {
    SharedPreferences.setMockInitialValues({
      'api_key': 'legacy-key',
      'api_secret': 'legacy-secret',
      'api_passphrase': 'legacy-passphrase',
    });
    final credentialsStore = MemoryCredentialsStore();
    final service = SettingsService(credentialsStore: credentialsStore);

    await service.load();
    service.apiKey = 'new-key';
    service.apiSecret = 'new-secret';
    service.apiPassphrase = 'new-passphrase';

    await service.save();

    expect(await credentialsStore.read('api_key'), 'new-key');
    expect(await credentialsStore.read('api_secret'), 'new-secret');
    expect(await credentialsStore.read('api_passphrase'), 'new-passphrase');

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('api_key'), isNull);
    expect(prefs.getString('api_secret'), isNull);
    expect(prefs.getString('api_passphrase'), isNull);
  });

  test('load normalizes unsafe risk settings from storage', () async {
    SharedPreferences.setMockInitialValues({
      'network': 'invalid',
      'timeframe': 'bad',
      'leverage': 0,
      'margin_sats': 0,
      'check_interval': 0,
      'ema_fast': 900,
      'ema_slow': 1,
      'ema_signal': 0,
      'take_profit_pct': -1.0,
      'stop_loss_pct': 150.0,
      'trailing_stop_pct': -5.0,
      'compounding_pct': 250.0,
    });
    final service = SettingsService(credentialsStore: MemoryCredentialsStore());

    await service.load();

    expect(service.network, 'testnet');
    expect(service.timeframe, '15m');
    expect(service.leverage, 1);
    expect(service.marginSats, 1);
    expect(service.checkInterval, 1);
    expect(service.emaFast, 499);
    expect(service.emaSlow, 500);
    expect(service.emaSignal, 2);
    expect(service.takeProfitPct, 0);
    expect(service.stopLossPct, 100);
    expect(service.trailingStopPct, 0.1);
    expect(service.compoundingPct, 100);
  });

  test('save persists normalized risk settings', () async {
    SharedPreferences.setMockInitialValues({});
    final service = SettingsService(credentialsStore: MemoryCredentialsStore());

    await service.load();
    service.network = 'bad';
    service.timeframe = 'bad';
    service.leverage = -10;
    service.marginSats = -1;
    service.checkInterval = -5;
    service.emaFast = 10;
    service.emaSlow = 10;
    service.emaSignal = 999;
    service.takeProfitPct = double.nan;
    service.stopLossPct = double.infinity;
    service.trailingStopPct = 0;
    service.compoundingPct = -1;

    await service.save();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('network'), 'testnet');
    expect(prefs.getString('timeframe'), '15m');
    expect(prefs.getInt('leverage'), 1);
    expect(prefs.getInt('margin_sats'), 1);
    expect(prefs.getInt('check_interval'), 1);
    expect(prefs.getInt('ema_fast'), 10);
    expect(prefs.getInt('ema_slow'), 11);
    expect(prefs.getInt('ema_signal'), 500);
    expect(prefs.getDouble('take_profit_pct'), 0);
    expect(prefs.getDouble('stop_loss_pct'), 0);
    expect(prefs.getDouble('trailing_stop_pct'), 0.1);
    expect(prefs.getDouble('compounding_pct'), 0.1);
  });
}
