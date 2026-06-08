import 'package:shared_preferences/shared_preferences.dart';

import '../src/settings/credentials_store.dart';

class SettingsService {
  SettingsService({CredentialsStore? credentialsStore})
      : _credentialsStore = credentialsStore ?? SecureCredentialsStore();

  late SharedPreferences _prefs;
  final CredentialsStore _credentialsStore;

  // Defaults
  String apiKey = '';
  String apiSecret = '';
  String apiPassphrase = '';
  String network = 'testnet';
  String timeframe = '1d';
  bool longOnly = true; // true = @Raicher Mode ON (long only) by default
  int leverage = 5;
  int marginSats = 50000;
  int checkInterval = 5;
  int emaFast = 9;
  int emaSlow = 21;
  int emaSignal = 50;
  double takeProfitPct = 0.0;
  double stopLossPct = 0.0;
  bool useTrailingStop = true; // default ON (@Raicher Mode default)
  double trailingStopPct = 1.0; // default 1% — best from backtest on 1D
  bool useCompounding = true; // default ON — use % of balance as margin
  double compoundingPct = 10.0; // % of balance to use per trade (default 10%)
  String language = 'pt_BR';

  static const allowedNetworks = {'testnet', 'mainnet'};
  static const allowedTimeframes = {
    '1m',
    '3m',
    '5m',
    '15m',
    '30m',
    '1h',
    '2h',
    '4h',
    '6h',
    '12h',
    '1d',
  };

  bool get hasCredentials =>
      apiKey.isNotEmpty && apiSecret.isNotEmpty && apiPassphrase.isNotEmpty;

  String get baseUrl => network == 'mainnet'
      ? 'https://api.lnmarkets.com'
      : 'https://api.testnet4.lnmarkets.com';

  int get candlesLimit => (emaSignal * 3).clamp(150, 500);

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    apiKey = await _loadCredential('api_key');
    apiSecret = await _loadCredential('api_secret');
    apiPassphrase = await _loadCredential('api_passphrase');
    network = _prefs.getString('network') ?? 'testnet';
    timeframe = _prefs.getString('timeframe') ?? '15m';
    leverage = _prefs.getInt('leverage') ?? 5;
    marginSats = _prefs.getInt('margin_sats') ?? 50000;
    checkInterval = _prefs.getInt('check_interval') ?? 5;
    emaFast = _prefs.getInt('ema_fast') ?? 9;
    emaSlow = _prefs.getInt('ema_slow') ?? 21;
    emaSignal = _prefs.getInt('ema_signal') ?? 50;
    takeProfitPct = _prefs.getDouble('take_profit_pct') ?? 0.0;
    stopLossPct = _prefs.getDouble('stop_loss_pct') ?? 0.0;
    useTrailingStop = _prefs.getBool('use_trailing_stop') ?? true;
    trailingStopPct = _prefs.getDouble('trailing_stop_pct') ?? 1.0;
    useCompounding = _prefs.getBool('use_compounding') ?? true;
    compoundingPct = _prefs.getDouble('compounding_pct') ?? 10.0;
    longOnly = _prefs.getBool('long_only') ?? true;
    language = _prefs.getString('language') ?? 'pt_BR';
    normalizeRiskSettings();
  }

  Future<void> save() async {
    normalizeRiskSettings();
    await _saveCredential('api_key', apiKey);
    await _saveCredential('api_secret', apiSecret);
    await _saveCredential('api_passphrase', apiPassphrase);
    await _prefs.setString('network', network);
    await _prefs.setString('timeframe', timeframe);
    await _prefs.setInt('leverage', leverage);
    await _prefs.setInt('margin_sats', marginSats);
    await _prefs.setInt('check_interval', checkInterval);
    await _prefs.setInt('ema_fast', emaFast);
    await _prefs.setInt('ema_slow', emaSlow);
    await _prefs.setInt('ema_signal', emaSignal);
    await _prefs.setDouble('take_profit_pct', takeProfitPct);
    await _prefs.setDouble('stop_loss_pct', stopLossPct);
    await _prefs.setBool('use_trailing_stop', useTrailingStop);
    await _prefs.setDouble('trailing_stop_pct', trailingStopPct);
    await _prefs.setBool('use_compounding', useCompounding);
    await _prefs.setDouble('compounding_pct', compoundingPct);
    await _prefs.setBool('long_only', longOnly);
    await _prefs.setString('language', language);
  }

  void normalizeRiskSettings() {
    if (!allowedNetworks.contains(network)) network = 'testnet';
    if (!allowedTimeframes.contains(timeframe)) timeframe = '15m';

    leverage = _clampInt(leverage, 1, 100);
    marginSats = _clampInt(marginSats, 1, 100000000);
    checkInterval = _clampInt(checkInterval, 1, 1440);

    emaFast = _clampInt(emaFast, 1, 499);
    emaSlow = _clampInt(emaSlow, 2, 500);
    if (emaSlow <= emaFast) {
      emaSlow = _clampInt(emaFast + 1, 2, 500);
      if (emaSlow <= emaFast) emaFast = emaSlow - 1;
    }
    emaSignal = _clampInt(emaSignal, 2, 500);

    takeProfitPct = _clampDouble(takeProfitPct, 0, 100);
    stopLossPct = _clampDouble(stopLossPct, 0, 100);
    trailingStopPct = _clampDouble(trailingStopPct, 0.1, 50);
    compoundingPct = _clampDouble(compoundingPct, 0.1, 100);
  }

  int _clampInt(int value, int min, int max) {
    if (value < min) return min;
    if (value > max) return max;
    return value;
  }

  double _clampDouble(double value, double min, double max) {
    if (!value.isFinite) return min;
    if (value < min) return min;
    if (value > max) return max;
    return value;
  }

  Future<String> _loadCredential(String key) async {
    final secureValue = await _credentialsStore.read(key);
    if (secureValue != null) {
      await _prefs.remove(key);
      return secureValue;
    }

    final legacyValue = _prefs.getString(key) ?? '';
    if (legacyValue.isNotEmpty) {
      await _credentialsStore.write(key, legacyValue);
      await _prefs.remove(key);
    }
    return legacyValue;
  }

  Future<void> _saveCredential(String key, String value) async {
    if (value.isEmpty) {
      await _credentialsStore.delete(key);
    } else {
      await _credentialsStore.write(key, value);
    }
    await _prefs.remove(key);
  }
}
