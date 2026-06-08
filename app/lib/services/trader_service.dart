import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

import 'lnmarkets_api.dart';
import 'binance_api.dart';
import 'indicators.dart';
import 'settings_service.dart';
import 'log_service.dart';
import '../src/clients/exchange_client.dart';
import '../src/clients/market_data_client.dart';
import '../src/platform/bot_runtime_controller.dart';
import '../src/trading/position_math.dart' as trading_math;

// ── Modelos ───────────────────────────────────────────────────────────────────

class SessionStats {
  int totalTrades = 0;
  int longTrades = 0;
  int shortTrades = 0;
  int netPnlSats = 0;
  int unrealizedPnl = 0;
  int get totalPnl => netPnlSats + unrealizedPnl;
}

class PositionState {
  final String? id;
  final String? side;
  final double? entryPrice;
  final double? tpPrice;
  final double? slPrice;
  final double? trailSlPrice; // current trailing SL level (null = not trailing)
  final DateTime? openedAt;

  const PositionState({
    this.id,
    this.side,
    this.entryPrice,
    this.tpPrice,
    this.slPrice,
    this.trailSlPrice,
    this.openedAt,
  });

  bool get hasPosition => id != null;

  factory PositionState.empty() => const PositionState();

  PositionState copyWith({double? trailSlPrice, double? slPrice}) =>
      PositionState(
        id: id,
        side: side,
        entryPrice: entryPrice,
        tpPrice: tpPrice,
        slPrice: slPrice ?? this.slPrice,
        trailSlPrice: trailSlPrice ?? this.trailSlPrice,
        openedAt: openedAt,
      );

  factory PositionState.fromJson(Map<String, dynamic> j) => PositionState(
        id: j['id'] as String?,
        side: j['side'] as String?,
        entryPrice: (j['entry_price'] as num?)?.toDouble(),
        tpPrice: (j['tp_price'] as num?)?.toDouble(),
        slPrice: (j['sl_price'] as num?)?.toDouble(),
        trailSlPrice: (j['trail_sl_price'] as num?)?.toDouble(),
        openedAt:
            j['opened_at'] != null ? DateTime.tryParse(j['opened_at']) : null,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'side': side,
        'entry_price': entryPrice,
        'tp_price': tpPrice,
        'sl_price': slPrice,
        'trail_sl_price': trailSlPrice,
        'opened_at': openedAt?.toIso8601String(),
      };
}

// ── Serviço principal ─────────────────────────────────────────────────────────

class TraderService extends ChangeNotifier {
  final SettingsService settings;
  final LogService log;
  final BotRuntimeController runtimeController;
  final ExchangeClient? _injectedExchangeClient;
  final MarketDataClient? _injectedMarketDataClient;
  final String positionStorageKey;

  TraderService({
    required this.settings,
    required this.log,
    ExchangeClient? exchangeClient,
    MarketDataClient? marketDataClient,
    BotRuntimeController? runtimeController,
    this.positionStorageKey = _defaultPositionKey,
  })  : runtimeController = runtimeController ?? createBotRuntimeController(),
        _injectedExchangeClient = exchangeClient,
        _injectedMarketDataClient = marketDataClient;

  // ── Estado observável ─────────────────────────────────────────────────────
  bool _running = false;
  TrendResult? _lastTrend;
  PositionState _position = PositionState.empty();
  SessionStats _stats = SessionStats();
  double _btcPrice = 0;
  int _balance = 0;
  DateTime? _startTime;

  bool get running => _running;
  TrendResult? get lastTrend => _lastTrend;
  PositionState get position => _position;
  SessionStats get stats => _stats;
  double get btcPrice => _btcPrice;
  int get balance => _balance;
  int get runtimeSecs =>
      _startTime == null ? 0 : DateTime.now().difference(_startTime!).inSeconds;

  // ── Timers ────────────────────────────────────────────────────────────────
  Timer? _cycleTimer;
  Timer? _pnlTimer;
  Timer? _priceTimer;
  bool _cycleRunning = false;

  late ExchangeClient _exchangeClient;
  late MarketDataClient _marketDataClient;
  late Indicators _indicators;

  // ── Persistência ──────────────────────────────────────────────────────────
  static const _defaultPositionKey = 'bot_position';

  Future<void> _savePosition(PositionState p) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(positionStorageKey, jsonEncode(p.toJson()));
  }

  Future<PositionState> _loadPosition() async {
    final prefs = await SharedPreferences.getInstance();
    final s = prefs.getString(positionStorageKey);
    if (s == null) return PositionState.empty();
    try {
      return PositionState.fromJson(jsonDecode(s) as Map<String, dynamic>);
    } catch (_) {
      return PositionState.empty();
    }
  }

  Future<void> _clearPosition() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(positionStorageKey);
  }

  Future<bool> _reconcileOpenPositions(List<dynamic> open) async {
    if (open.isEmpty) {
      if (_position.hasPosition) {
        log.warning(
            'Posicao local ${_position.id} nao aparece mais na LN Markets. Limpando estado local.');
        _position = PositionState.empty();
        await _clearPosition();
      }
      _stats.unrealizedPnl = 0;
      return false;
    }

    final remotePositions =
        open.map(_stringKeyedMap).whereType<Map<String, dynamic>>().toList();
    if (remotePositions.isEmpty) {
      log.warning(
          'LN Markets retornou posicao aberta em formato inesperado. Abertura bloqueada.');
      _stats.unrealizedPnl = 0;
      return true;
    }

    _stats.unrealizedPnl = remotePositions.fold<int>(
      0,
      (total, position) =>
          total +
          (_readNum(position, const [
                'pl',
                'pnl',
                'profit',
                'unrealizedPnl',
                'unrealized_pnl',
              ])?.toInt() ??
              0),
    );

    if (remotePositions.length > 1) {
      log.warning(
          'LN Markets possui ${remotePositions.length} posicoes abertas. Nova entrada bloqueada.');
    }

    final localId = _position.id;
    Map<String, dynamic>? selected;
    if (localId != null) {
      for (final remote in remotePositions) {
        if (_readString(remote, const ['id']) == localId) {
          selected = remote;
          break;
        }
      }
    }
    selected ??= remotePositions.first;

    final remotePosition = _positionFromRemote(selected, existing: _position);
    if (remotePosition.id == null) {
      log.warning(
          'Posicao remota aberta sem id reconhecido. Nova entrada bloqueada.');
      return true;
    }

    if (_position.id != remotePosition.id) {
      log.warning(
          'Estado local sincronizado com posicao remota ${remotePosition.id}.');
    }

    _position = remotePosition;
    await _savePosition(_position);
    return true;
  }

  Map<String, dynamic>? _stringKeyedMap(dynamic value) {
    if (value is! Map) return null;
    return value.map((key, value) => MapEntry(key.toString(), value));
  }

  PositionState _positionFromRemote(
    Map<String, dynamic> remote, {
    required PositionState existing,
  }) {
    final id = _readString(remote, const ['id']);
    final sameId = id != null && id == existing.id;
    final side = _normalizeSide(_readString(remote, const ['side', 'type']));
    final entryPrice = _readDouble(remote, const [
      'entryPrice',
      'entry_price',
      'entry',
      'price',
    ]);
    final tpPrice = _readDouble(remote, const [
      'takeprofit',
      'takeProfit',
      'take_profit',
      'tp_price',
      'tp',
    ]);
    final slPrice = _readDouble(remote, const [
      'stoploss',
      'stopLoss',
      'stop_loss',
      'sl_price',
      'sl',
    ]);
    final openedAt = _readDateTime(remote, const [
      'opened_at',
      'openedAt',
      'created_at',
      'createdAt',
      'market_filled_ts',
      'creation_ts',
    ]);
    final trailSlPrice = sameId
        ? existing.trailSlPrice
        : settings.useTrailingStop && side == 'long'
            ? slPrice
            : null;

    return PositionState(
      id: id,
      side: side ?? (sameId ? existing.side : null),
      entryPrice: entryPrice ?? (sameId ? existing.entryPrice : null),
      tpPrice: tpPrice ?? (sameId ? existing.tpPrice : null),
      slPrice: slPrice ?? (sameId ? existing.slPrice : null),
      trailSlPrice: trailSlPrice,
      openedAt: openedAt ?? (sameId ? existing.openedAt : DateTime.now()),
    );
  }

  String? _normalizeSide(String? side) {
    switch (side?.toLowerCase()) {
      case 'buy':
      case 'long':
        return 'long';
      case 'sell':
      case 'short':
        return 'short';
      default:
        return side?.toLowerCase();
    }
  }

  String? _readString(Map<String, dynamic> source, List<String> keys) {
    final value = _readValue(source, keys);
    if (value == null) return null;
    if (value is String) return value;
    return value.toString();
  }

  double? _readDouble(Map<String, dynamic> source, List<String> keys) =>
      _readNum(source, keys)?.toDouble();

  num? _readNum(Map<String, dynamic> source, List<String> keys) {
    final value = _readValue(source, keys);
    if (value is num) return value;
    if (value is String) return num.tryParse(value);
    return null;
  }

  DateTime? _readDateTime(Map<String, dynamic> source, List<String> keys) {
    final value = _readValue(source, keys);
    if (value is DateTime) return value;
    if (value is String) {
      final parsed = DateTime.tryParse(value);
      if (parsed != null) return parsed;
      final timestamp = num.tryParse(value);
      if (timestamp != null) return _dateTimeFromUnix(timestamp);
    }
    if (value is num) return _dateTimeFromUnix(value);
    return null;
  }

  DateTime? _dateTimeFromUnix(num value) {
    final timestamp = value.toInt();
    if (timestamp <= 0) return null;
    final millis = timestamp > 10000000000 ? timestamp : timestamp * 1000;
    return DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true).toLocal();
  }

  dynamic _readValue(Map<String, dynamic> source, List<String> keys) {
    for (final key in keys) {
      if (source.containsKey(key) && source[key] != null) {
        return source[key];
      }
    }
    return null;
  }

  // ── Start / Stop ──────────────────────────────────────────────────────────

  Future<void> start() async {
    if (_running) return;
    _exchangeClient =
        _injectedExchangeClient ?? LiveExchangeClient(LNMarketsAPI(settings));
    _marketDataClient =
        _injectedMarketDataClient ?? LiveMarketDataClient(BinanceAPI());
    _indicators = Indicators(settings);

    _stats = SessionStats();
    _startTime = DateTime.now();
    _position = await _loadPosition();

    try {
      final user = await _exchangeClient.getUser();
      _balance = ((user['balance'] as num?) ?? 0).toInt();
      log.info('Conectado: ${user['username']} | saldo=$_balance sats');
    } catch (e) {
      log.error('Falha ao conectar com LN Markets: $e');
      return;
    }

    _running = true;
    notifyListeners();

    // Inicia serviço em primeiro plano para manter o app ativo em background
    await runtimeController.start(
      title: 'LN Markets Bot',
      text: 'Bot em execução…',
    );

    await _runCycle();
    if (!_running) return;

    _cycleTimer = Timer.periodic(
      Duration(minutes: settings.checkInterval),
      (_) => _runCycle(),
    );

    _pnlTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => _updateUnrealizedPnl(),
    );

    _priceTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _updatePrice(),
    );
  }

  void stop() {
    _running = false;
    _cycleTimer?.cancel();
    _pnlTimer?.cancel();
    _priceTimer?.cancel();
    _stats.unrealizedPnl = 0;
    log.info('Bot encerrado.');
    notifyListeners();
    runtimeController.stop();
  }

  // ── Ciclo de verificação ──────────────────────────────────────────────────

  Future<void> _runCycle() async {
    if (_cycleRunning) {
      log.warning(
          'Ciclo anterior ainda em execucao. Pulando ciclo sobreposto.');
      return;
    }
    _cycleRunning = true;
    try {
      await _runCycleCore();
    } finally {
      _cycleRunning = false;
    }
  }

  Future<void> _runCycleCore() async {
    log.info('─' * 50);
    log.info('Iniciando ciclo: ${DateTime.now()}');

    TrendResult result;
    try {
      final candles = await _marketDataClient.fetchCandles(
          settings.timeframe, settings.candlesLimit);
      result = _indicators.compute(candles);
      _lastTrend = result;
      _btcPrice = result.price;
      log.info(
        'Trend | Preço: \$${result.price} | '
        'EMA${settings.emaFast}: ${result.emaFast} | '
        'EMA${settings.emaSlow}: ${result.emaSlow} | '
        'Sinal: ${result.signal ?? 'neutro'} | '
        'BB: ${result.bbFilter ? 'ok' : 'filt'} | '
        'MACD: ${result.macdFilter ? 'ok' : 'filt'}',
      );
    } catch (e) {
      log.error('Erro ao buscar indicadores: $e');
      notifyListeners();
      return;
    }

    var hasRemoteOpenPosition = false;
    try {
      final open = await _exchangeClient.getOpenPositions();
      hasRemoteOpenPosition = await _reconcileOpenPositions(open);
    } catch (e) {
      log.error('Erro ao buscar posicoes: $e');
      notifyListeners();
      return;
    }

    if (hasRemoteOpenPosition && !_position.hasPosition) {
      log.warning(
          'Posicao remota aberta sem id reconhecido. Abertura bloqueada neste ciclo.');
      notifyListeners();
      return;
    }

    // Trailing SL update — runs before signal logic so SL is always current
    if (settings.useTrailingStop &&
        _position.hasPosition &&
        _position.side == 'long') {
      final newSl = trading_math.computeLongTrailingStop(
        price: result.price,
        trailingStopPct: settings.trailingStopPct,
      );
      final currentTrailSl = _position.trailSlPrice;
      if (currentTrailSl == null || newSl > currentTrailSl) {
        try {
          await _exchangeClient.setStopLoss(_position.id!, newSl);
          _position = _position.copyWith(trailSlPrice: newSl, slPrice: newSl);
          await _savePosition(_position);
          log.info('Trailing SL → \$${newSl.toStringAsFixed(2)} '
              '(${settings.trailingStopPct}% abaixo de \$${result.price.toStringAsFixed(2)})');
        } catch (e) {
          log.warning('Falha ao atualizar trailing SL: $e');
        }
      }
    }

    final signal = result.signal;

    // Atualiza notificação com estado atual
    if (_running) {
      final statusText = signal != null
          ? 'Sinal: ${signal.toUpperCase()} | BTC \$${result.price.toStringAsFixed(0)}'
          : 'Neutro | BTC \$${result.price.toStringAsFixed(0)}';
      await runtimeController.update(title: 'LN Markets Bot', text: statusText);
    }

    // When longOnly, treat short signals as neutral
    final effectiveSignal = trading_math.effectiveSignal(
      longOnly: settings.longOnly,
      signal: signal,
    );

    if (!_position.hasPosition) {
      if (effectiveSignal != null) {
        // BB + MACD filters apply only to long entries
        final filtered = effectiveSignal == 'long' &&
            (!result.bbFilter || !result.macdFilter);
        if (filtered) {
          log.info('Sinal long bloqueado por filtro — '
              'BB: ${result.bbFilter ? 'ok' : 'falhou'} | '
              'MACD: ${result.macdFilter ? 'ok' : 'falhou'}. Aguardando...');
        } else {
          log.info('Sem posição. Abrindo $effectiveSignal...');
          await _openNew(effectiveSignal, result.price);
        }
      } else {
        log.info(settings.longOnly && signal == 'short'
            ? 'Modo Long Only: sinal short ignorado. Aguardando...'
            : 'Sem sinal confirmado. Aguardando...');
      }
      notifyListeners();
      return;
    }

    if (effectiveSignal != null && _position.side != effectiveSignal) {
      log.info(
          'INVERSÃO! ${_position.side?.toUpperCase()} → ${effectiveSignal.toUpperCase()}');
      try {
        final closeResult = await _exchangeClient.closePosition(_position.id!);
        final pl = ((closeResult['pl'] as num?) ?? 0).toInt();
        _stats.netPnlSats += pl;
        log.info('Posição fechada | P&L = ${pl > 0 ? '+' : ''}$pl sats');
        _position = PositionState.empty();
        await _clearPosition();
      } catch (e) {
        log.error('Erro ao fechar posição: $e');
        notifyListeners();
        return;
      }
      final filteredFlip =
          effectiveSignal == 'long' && (!result.bbFilter || !result.macdFilter);
      if (!filteredFlip) {
        await _openNew(effectiveSignal, result.price);
      } else {
        log.info('Inversão long bloqueada por filtro — '
            'BB: ${result.bbFilter ? 'ok' : 'falhou'} | '
            'MACD: ${result.macdFilter ? 'ok' : 'falhou'}.');
      }
      notifyListeners();
      return;
    }

    // In longOnly mode, close position when short signal fires (don't reopen short)
    if (settings.longOnly &&
        signal == 'short' &&
        _position.hasPosition &&
        _position.side == 'long') {
      log.info('Modo Long Only: sinal short → fechando long sem reabrir.');
      try {
        final closeResult = await _exchangeClient.closePosition(_position.id!);
        final pl = ((closeResult['pl'] as num?) ?? 0).toInt();
        _stats.netPnlSats += pl;
        log.info('Posição fechada | P&L = ${pl > 0 ? '+' : ''}$pl sats');
        _position = PositionState.empty();
        await _clearPosition();
      } catch (e) {
        log.error('Erro ao fechar posição: $e');
      }
      notifyListeners();
      return;
    }

    log.info('Tendência mantida (${effectiveSignal ?? 'neutro'}). '
        'Posição ${_position.side?.toUpperCase() ?? '?'} continua.');

    try {
      final user = await _exchangeClient.getUser();
      _balance = ((user['balance'] as num?) ?? 0).toInt();
    } catch (_) {}

    notifyListeners();
  }

  Future<void> _openNew(String signal, double currentPrice) async {
    try {
      final side = signal == 'long' ? 'buy' : 'sell';

      // Compound mode: use % of current balance as margin
      int? marginOverride;
      if (settings.useCompounding && _balance > 0) {
        marginOverride = trading_math.computeCompoundMargin(
          balanceSats: _balance,
          compoundingPct: settings.compoundingPct,
        );
        log.info(
            'Compound margin: ${settings.compoundingPct}% × $_balance sats = $marginOverride sats');
      }

      final pos = await _exchangeClient.openPosition(
        side,
        marginSats: marginOverride,
      );

      _stats.totalTrades++;
      if (signal == 'long') {
        _stats.longTrades++;
      } else {
        _stats.shortTrades++;
      }

      final apiEntry = (pos['entryPrice'] as num?)?.toDouble() ??
          (pos['entry_price'] as num?)?.toDouble();
      final entry =
          (apiEntry != null && apiEntry > 0) ? apiEntry : currentPrice;

      // Compute TP/SL absolute prices locally for display
      final isLong = signal == 'long';
      final tp = settings.takeProfitPct;
      final sl = settings.stopLossPct;
      final tpSl = trading_math.computeTpSlPrices(
        side: signal,
        entryPrice: entry,
        takeProfitPct: tp,
        stopLossPct: sl,
      );

      _position = PositionState(
        id: pos['id'] as String?,
        side: signal,
        entryPrice: entry,
        tpPrice: tpSl.takeProfit,
        slPrice: tpSl.stopLoss,
        openedAt: DateTime.now(),
      );
      await _savePosition(_position);

      log.info('Posição aberta: $signal | id=${_position.id} | entry=\$$entry');

      if (_position.id != null) {
        if (settings.useTrailingStop && isLong) {
          // Set initial trailing SL; subsequent cycles will trail it upward
          final initialTrailSl = trading_math.computeLongTrailingStop(
            price: entry,
            trailingStopPct: settings.trailingStopPct,
          );
          try {
            await _exchangeClient.setStopLoss(_position.id!, initialTrailSl);
            _position = _position.copyWith(
                trailSlPrice: initialTrailSl, slPrice: initialTrailSl);
            await _savePosition(_position);
            log.info(
                'Trailing SL inicial: \$${initialTrailSl.toStringAsFixed(2)} '
                '(${settings.trailingStopPct}% abaixo)');
          } catch (e) {
            await _closeUnprotectedPosition(_position.id!, e);
            return;
          }
          // Still apply TP if configured
          if (tp > 0) {
            try {
              await _exchangeClient.applyTpSl(_position.id!, signal, entry);
              log.info('TP aplicado | TP=$tp%');
            } catch (e) {
              await _closeUnprotectedPosition(_position.id!, e);
              return;
            }
          }
        } else {
          try {
            await _exchangeClient.applyTpSl(_position.id!, signal, entry);
            if (tp > 0 || sl > 0) {
              log.info('TP/SL aplicados | TP=$tp% | SL=$sl%');
            }
          } catch (e) {
            await _closeUnprotectedPosition(_position.id!, e);
            return;
          }
        }
      } else {
        log.error(
            'Posicao aberta sem id. Bot pausado para evitar operacao sem protecao.');
        stop();
      }
    } catch (e) {
      log.error('Erro ao abrir posição: $e');
    }
  }

  // ── Atualizações periódicas ───────────────────────────────────────────────

  Future<void> _closeUnprotectedPosition(
    String positionId,
    Object protectionError,
  ) async {
    log.error(
        'Falha ao proteger posicao $positionId: $protectionError. Fechando defensivamente.');
    try {
      final closeResult = await _exchangeClient.closePosition(positionId);
      final pl = ((closeResult['pl'] as num?) ?? 0).toInt();
      _stats.netPnlSats += pl;
      log.warning(
          'Posicao $positionId fechada defensivamente | P&L = ${pl > 0 ? '+' : ''}$pl sats');
    } catch (closeError) {
      log.error(
          'Falha ao fechar posicao sem protecao $positionId: $closeError');
    } finally {
      _position = PositionState.empty();
      await _clearPosition();
      stop();
    }
  }

  Future<void> _updateUnrealizedPnl() async {
    if (!_running) return;
    try {
      final open = await _exchangeClient.getOpenPositions();
      _stats.unrealizedPnl =
          open.isNotEmpty ? ((open[0]['pl'] as num?) ?? 0).toInt() : 0;
      notifyListeners();
    } catch (_) {}
  }

  Future<void> _updatePrice() async {
    if (!_running) return;
    try {
      _btcPrice = await _marketDataClient.fetchPrice();
      notifyListeners();
    } catch (_) {}
  }

  Future<void> fetchPriceOnce() async {
    try {
      final marketDataClient =
          _injectedMarketDataClient ?? LiveMarketDataClient(BinanceAPI());
      _btcPrice = await marketDataClient.fetchPrice();
      notifyListeners();
    } catch (_) {}
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}
