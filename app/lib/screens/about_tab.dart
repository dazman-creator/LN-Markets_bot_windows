import 'package:flutter/material.dart';
import '../app_theme.dart';
import '../app_version.dart';
import '../i18n.dart';

class AboutTab extends StatelessWidget {
  static const _thanks = [
    ('Fabio Akita', 'AkitaOnRails', 'Dev lendário brasileiro'),
    ('BitDov', 'BitDov', 'Educação Bitcoin de qualidade'),
    ('Daniel Fraga', 'DanielFragaBTC', 'Liberdade e filosofia Bitcoin'),
    ('Renato Amoedo', 'RenatoAmoedo', 'Empreendedorismo e inovação'),
    ('Allan Schramm', 'AllanSchramm', 'Comunidade e análise técnica'),
    ('Marcell Pechmann', 'MarcellPechmann', 'Educação financeira e Bitcoin'),
  ];

  const AboutTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: Text(t('about_title'))),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // ── Logo ──────────────────────────────────────────────────────────
          const Center(child: Text('⚡', style: TextStyle(fontSize: 72))),
          const SizedBox(height: 8),
          Center(
            child: Text(t('about_title'),
                style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textMain)),
          ),
          Center(
            child: Text('${t('about_version_label')} ${AppVersion.version}',
                style:
                    const TextStyle(fontSize: 13, color: AppColors.textMuted)),
          ),
          const SizedBox(height: 20),

          // ── Descrição ─────────────────────────────────────────────────────
          _card(
              child: Center(
            child: Text(t('about_desc'),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14, height: 1.6)),
          )),
          const SizedBox(height: 12),

          // ── Créditos ──────────────────────────────────────────────────────
          _card(
              child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(t('about_made'),
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: AppColors.orange)),
              const SizedBox(height: 4),
              Text(t('about_dev'),
                  style: const TextStyle(
                      fontSize: 13, color: AppColors.textMuted)),
            ],
          )),
          const SizedBox(height: 12),

          // ── Agradecimentos ────────────────────────────────────────────────
          _card(
              child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Text(t('about_thanks'),
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: AppColors.orange)),
              ),
              const SizedBox(height: 14),
              ..._thanks.map((e) => _thankRow(e.$1, e.$3)),
            ],
          )),
          const SizedBox(height: 12),

          // ── Risco ─────────────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF2A1010),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(t('about_risk'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 12, color: Color(0xFFFF6B6B), height: 1.6)),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _card({required Widget child}) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: AppColors.card, borderRadius: BorderRadius.circular(12)),
        child: child,
      );

  Widget _thankRow(String name, String desc) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('★  ',
              style: TextStyle(color: AppColors.orange, fontSize: 15)),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name,
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textMain)),
              Text(desc,
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.textMuted)),
            ]),
          ),
        ]),
      );
}
