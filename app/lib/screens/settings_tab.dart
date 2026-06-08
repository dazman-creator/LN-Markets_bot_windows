import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../app_theme.dart';
import '../i18n.dart';
import '../services/settings_service.dart';
import '../services/trader_service.dart';

const _ytUrl = 'https://youtu.be/Lo1VRofjogk?si=HdKO8aYM5CnWhHyy';
const _timeframes = [
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
  '1d'
];

// Recommended check interval (minutes) per timeframe
const _tfInterval = {
  '1m': 1,
  '3m': 3,
  '5m': 5,
  '15m': 15,
  '30m': 30,
  '1h': 60,
  '2h': 120,
  '4h': 240,
  '6h': 360,
  '12h': 720,
  '1d': 1440,
};

class SettingsTab extends StatefulWidget {
  final SettingsService settings;
  final TraderService traderService;
  final VoidCallback onSaved;
  const SettingsTab({
    super.key,
    required this.settings,
    required this.traderService,
    required this.onSaved,
  });

  @override
  State<SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<SettingsTab> {
  // Controllers
  late final TextEditingController _apiKey, _apiSecret, _apiPass;
  late final TextEditingController _leverage, _margin, _interval;
  late final TextEditingController _emaFast, _emaSlow, _emaSignal;
  late final TextEditingController _tp, _sl, _trailPct, _compoundPct;

  String _timeframe = '15m';
  String _network = 'mainnet';
  bool _longOnly = true;
  bool _useTrailingStop = true;
  bool _useCompounding = true;
  String? _savedMsg;

  @override
  void initState() {
    super.initState();
    final s = widget.settings;
    _apiKey = TextEditingController(text: s.apiKey);
    _apiSecret = TextEditingController(text: s.apiSecret);
    _apiPass = TextEditingController(text: s.apiPassphrase);
    _leverage = TextEditingController(text: '${s.leverage}');
    _margin = TextEditingController(text: '${s.marginSats}');
    _interval = TextEditingController(text: '${s.checkInterval}');
    _emaFast = TextEditingController(text: '${s.emaFast}');
    _emaSlow = TextEditingController(text: '${s.emaSlow}');
    _emaSignal = TextEditingController(text: '${s.emaSignal}');
    _tp = TextEditingController(text: '${s.takeProfitPct}');
    _sl = TextEditingController(text: '${s.stopLossPct}');
    _trailPct = TextEditingController(text: '${s.trailingStopPct}');
    _compoundPct = TextEditingController(text: '${s.compoundingPct}');
    _timeframe = s.timeframe;
    _network = s.network;
    _longOnly = s.longOnly;
    _useTrailingStop = s.useTrailingStop;
    _useCompounding = s.useCompounding;
  }

  @override
  void dispose() {
    for (final c in [
      _apiKey,
      _apiSecret,
      _apiPass,
      _leverage,
      _margin,
      _interval,
      _emaFast,
      _emaSlow,
      _emaSignal,
      _tp,
      _sl,
      _trailPct,
      _compoundPct
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final key = _apiKey.text.trim();
    final sec = _apiSecret.text.trim();
    final pass = _apiPass.text.trim();

    if (key.isEmpty || sec.isEmpty || pass.isEmpty) {
      setState(() => _savedMsg = t('set_error_creds'));
      return;
    }

    final s = widget.settings;
    s.apiKey = key;
    s.apiSecret = sec;
    s.apiPassphrase = pass;
    s.network = _network;
    s.timeframe = _timeframe;
    s.leverage = int.tryParse(_leverage.text) ?? 5;
    s.marginSats = int.tryParse(_margin.text) ?? 50000;
    s.checkInterval = int.tryParse(_interval.text) ?? 5;
    s.emaFast = int.tryParse(_emaFast.text) ?? 9;
    s.emaSlow = int.tryParse(_emaSlow.text) ?? 21;
    s.emaSignal = int.tryParse(_emaSignal.text) ?? 50;
    s.takeProfitPct = double.tryParse(_tp.text) ?? 0;
    s.stopLossPct = double.tryParse(_sl.text) ?? 0;
    s.useTrailingStop = _useTrailingStop;
    s.trailingStopPct = double.tryParse(_trailPct.text) ?? 1.0;
    s.useCompounding = _useCompounding;
    s.compoundingPct = double.tryParse(_compoundPct.text) ?? 10.0;
    s.longOnly = _longOnly;
    await s.save();

    setState(() {
      _syncFieldsFromSettings();
      _savedMsg = t('set_saved');
    });
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) setState(() => _savedMsg = null);
    });
    widget.onSaved();
  }

  Future<void> _setLang(String lang) async {
    AppLocalizations.setLanguage(lang);
    widget.settings.language = lang;
    await widget.settings.save();
    setState(() => _syncFieldsFromSettings());
    widget.onSaved();
  }

  void _syncFieldsFromSettings() {
    final s = widget.settings;
    _leverage.text = '${s.leverage}';
    _margin.text = '${s.marginSats}';
    _interval.text = '${s.checkInterval}';
    _emaFast.text = '${s.emaFast}';
    _emaSlow.text = '${s.emaSlow}';
    _emaSignal.text = '${s.emaSignal}';
    _tp.text = '${s.takeProfitPct}';
    _sl.text = '${s.stopLossPct}';
    _trailPct.text = '${s.trailingStopPct}';
    _compoundPct.text = '${s.compoundingPct}';
    _timeframe = s.timeframe;
    _network = s.network;
    _longOnly = s.longOnly;
    _useTrailingStop = s.useTrailingStop;
    _useCompounding = s.useCompounding;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: Text(t('set_title'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Idioma ───────────────────────────────────────────────────────
          _sectionHeader(t('set_language')),
          Row(
            children: AppLocalizations.languages.map((lang) {
              final active = AppLocalizations.language == lang;
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          active ? AppColors.orange : AppColors.card,
                      foregroundColor:
                          active ? Colors.black : AppColors.textMuted,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    onPressed: () => _setLang(lang),
                    child: Text(
                      '${AppLocalizations.flags[lang]}  '
                      '${AppLocalizations.names[lang]}',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 8),

          // ── API ──────────────────────────────────────────────────────────
          _sectionHeader(t('set_api_section')),
          _ytButton(),
          const SizedBox(height: 8),
          // Info card — each user must fill with their own credentials
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF0D1F0D),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF1E5C1E)),
            ),
            child: Row(children: [
              const Icon(Icons.info_outline,
                  size: 16, color: Color(0xFF4CAF50)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  t('set_api_info'),
                  style: const TextStyle(
                      fontSize: 11.5, color: Color(0xFF81C784), height: 1.4),
                ),
              ),
            ]),
          ),
          _field(t('set_api_key'), _apiKey, hint: t('set_api_key_hint')),
          _field(t('set_api_secret'), _apiSecret,
              hint: t('set_api_secret_hint'), obscure: true),
          _field(t('set_api_pass'), _apiPass,
              hint: t('set_api_pass_hint'), obscure: true),
          const SizedBox(height: 8),
          _label(t('set_network')),
          Row(children: [
            _radio('mainnet', t('set_mainnet')),
            const SizedBox(width: 24),
            _radio('testnet', t('set_testnet')),
          ]),

          // ── Trading ──────────────────────────────────────────────────────
          _sectionHeader(t('set_trading_section')),
          _label(t('set_timeframe')),
          DropdownButtonFormField<String>(
            initialValue: _timeframe,
            dropdownColor: AppColors.card,
            style: const TextStyle(color: AppColors.textMain),
            decoration: const InputDecoration(),
            items: _timeframes
                .map((tf) => DropdownMenuItem(value: tf, child: Text(tf)))
                .toList(),
            onChanged: (v) {
              setState(() {
                _timeframe = v!;
                _interval.text = '${_tfInterval[v] ?? 5}';
              });
            },
          ),
          const SizedBox(height: 8),
          _field(t('set_leverage'), _leverage,
              keyboardType: TextInputType.number),
          _field(t('set_interval'), _interval,
              keyboardType: TextInputType.number),

          // ── EMAs ──────────────────────────────────────────────────────────
          _sectionHeader(t('set_ema_section')),
          _field(t('set_ema_fast'), _emaFast,
              keyboardType: TextInputType.number),
          _field(t('set_ema_slow'), _emaSlow,
              keyboardType: TextInputType.number),
          _field(t('set_ema_signal'), _emaSignal,
              keyboardType: TextInputType.number),

          // ── Risco ─────────────────────────────────────────────────────────
          _sectionHeader(t('set_risk_section')),
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color:
                  _longOnly ? const Color(0xFF0D1F0D) : const Color(0xFF1F0D0D),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: _longOnly
                    ? const Color(0xFF1E5C1E)
                    : const Color(0xFF5C1E1E),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        t('set_long_only'),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: _longOnly
                              ? const Color(0xFF81C784)
                              : const Color(0xFFE57373),
                        ),
                      ),
                    ),
                    Switch(
                      // ON = @Raicher Mode active = long only (longOnly=true)
                      value: _longOnly,
                      activeThumbColor: AppColors.green,
                      inactiveTrackColor: AppColors.red.withValues(alpha: 0.4),
                      onChanged: (v) => setState(() => _longOnly = v),
                    ),
                  ],
                ),
                Text(
                  t('set_long_only_hint'),
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textMuted,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(t('set_tp_hint'),
                style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textMuted,
                    fontStyle: FontStyle.italic)),
          ),
          _field(t('set_tp'), _tp,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true)),
          // Trailing Stop toggle
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color:
                  _useTrailingStop ? const Color(0xFF0D1A2B) : AppColors.card,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: _useTrailingStop
                    ? const Color(0xFF1E4A7C)
                    : AppColors.divider,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        t('set_trailing_stop'),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: _useTrailingStop
                              ? const Color(0xFF64B5F6)
                              : AppColors.textMuted,
                        ),
                      ),
                    ),
                    Switch(
                      value: _useTrailingStop,
                      activeThumbColor: const Color(0xFF2196F3),
                      inactiveTrackColor: AppColors.card,
                      onChanged: (v) => setState(() => _useTrailingStop = v),
                    ),
                  ],
                ),
                Text(
                  t('set_trailing_stop_hint'),
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textMuted,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
          if (_useTrailingStop)
            _field(t('set_trailing_pct'), _trailPct,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true))
          else
            _field(t('set_sl'), _sl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true)),

          // Compound margin toggle
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: _useCompounding ? const Color(0xFF1A0D2B) : AppColors.card,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: _useCompounding
                    ? const Color(0xFF5C1E9C)
                    : AppColors.divider,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        t('set_compounding'),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: _useCompounding
                              ? const Color(0xFFCE93D8)
                              : AppColors.textMuted,
                        ),
                      ),
                    ),
                    Switch(
                      value: _useCompounding,
                      activeThumbColor: const Color(0xFF9C27B0),
                      inactiveTrackColor: AppColors.card,
                      onChanged: (v) => setState(() => _useCompounding = v),
                    ),
                  ],
                ),
                Text(
                  t('set_compounding_hint'),
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textMuted,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
          if (_useCompounding)
            _field(t('set_compounding_pct'), _compoundPct,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true))
          else
            _field(t('set_margin'), _margin,
                keyboardType: TextInputType.number),

          const SizedBox(height: 24),

          // ── Salvar ────────────────────────────────────────────────────────
          ElevatedButton(
            onPressed: _save,
            child: Text(t('set_save')),
          ),

          if (_savedMsg != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                _savedMsg!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _savedMsg == t('set_saved')
                      ? AppColors.green
                      : AppColors.red,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  // ── Helpers de layout ──────────────────────────────────────────────────────

  Widget _sectionHeader(String text) => Padding(
        padding: const EdgeInsets.only(top: 20, bottom: 8),
        child: Text(text,
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: AppColors.orange)),
      );

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(text,
            style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
      );

  Widget _field(String label, TextEditingController ctrl,
          {bool obscure = false, TextInputType? keyboardType, String? hint}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextField(
          controller: ctrl,
          obscureText: obscure,
          keyboardType: keyboardType,
          style: const TextStyle(color: AppColors.textMain, fontSize: 14),
          decoration: InputDecoration(
            labelText: label,
            hintText: hint,
            hintStyle: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 12,
                fontStyle: FontStyle.italic),
            suffixIcon: obscure
                ? const Icon(Icons.lock_outline,
                    size: 16, color: AppColors.textMuted)
                : null,
          ),
        ),
      );

  Widget _radio(String value, String label) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Radio<String>(
            value: value,
            // ignore: deprecated_member_use
            groupValue: _network,
            activeColor: AppColors.orange,
            // ignore: deprecated_member_use
            onChanged: (v) => setState(() => _network = v!),
          ),
          Text(label,
              style: const TextStyle(color: AppColors.textMain, fontSize: 13)),
        ],
      );

  Widget _ytButton() => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFFFF4444),
            side: const BorderSide(color: Color(0xFF3A0A0A)),
            backgroundColor: const Color(0xFF1A0505),
            padding: const EdgeInsets.symmetric(vertical: 12),
          ),
          icon: const Icon(Icons.play_circle_outline, size: 18),
          label: Text(t('set_yt_btn'), style: const TextStyle(fontSize: 12)),
          onPressed: () async {
            final uri = Uri.parse(_ytUrl);
            if (await canLaunchUrl(uri)) await launchUrl(uri);
          },
        ),
      );
}
