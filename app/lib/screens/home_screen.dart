import 'package:flutter/material.dart';
import '../i18n.dart';
import '../services/settings_service.dart';
import '../services/trader_service.dart';
import '../services/log_service.dart';
import '../services/update_service.dart';
import '../src/platform/bot_runtime_controller.dart';
import '../app_theme.dart';
import '../widgets/sponsor_banner.dart';
import 'dashboard_tab.dart';
import 'settings_tab.dart';
import 'logs_tab.dart';
import 'sponsors_tab.dart';
import 'about_tab.dart';

class HomeScreen extends StatefulWidget {
  final SettingsService settings;
  final TraderService traderService;
  final LogService logService;
  final BotRuntimeController runtimeController;
  final bool showSponsorBanner;
  final bool enableExternalEffects;

  const HomeScreen({
    super.key,
    required this.settings,
    required this.traderService,
    required this.logService,
    required this.runtimeController,
    this.showSponsorBanner = true,
    this.enableExternalEffects = true,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;
  bool _checkedForUpdates = false;

  // Desktop width threshold
  static const double _desktopBreak = 600;

  @override
  void initState() {
    super.initState();
    if (!widget.settings.hasCredentials) _tab = 1;
    if (widget.enableExternalEffects) {
      widget.traderService.fetchPriceOnce();
      Future.delayed(const Duration(seconds: 2),
          () => widget.runtimeController.requestBatteryOptimization());
      WidgetsBinding.instance.addPostFrameCallback((_) => _checkForUpdates());
    }
  }

  void _onTab(int i) => setState(() => _tab = i);

  Future<void> _checkForUpdates() async {
    if (_checkedForUpdates) return;
    _checkedForUpdates = true;

    final service = UpdateService();
    try {
      final release = await service.findLatestAvailable();
      if (!mounted || release == null) return;

      final install = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(t('update_title')),
          content: Text(
            t('update_body').replaceAll('{version}', release.tagName),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(t('update_later')),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(t('update_install')),
            ),
          ],
        ),
      );

      if (!mounted || install != true) return;
      if (widget.traderService.running) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(t('update_running'))),
        );
        return;
      }

      await _downloadAndInstallUpdate(service, release);
    } catch (_) {
      // Startup update checks should never block normal app usage.
    } finally {
      service.dispose();
    }
  }

  Future<void> _downloadAndInstallUpdate(
    UpdateService service,
    UpdateRelease release,
  ) async {
    var dialogOpen = true;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        content: Row(
          children: [
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 16),
            Expanded(child: Text(t('update_downloading'))),
          ],
        ),
      ),
    );

    try {
      final staged = await service.downloadAndStage(release);
      if (mounted && dialogOpen) {
        Navigator.of(context).pop();
        dialogOpen = false;
      }
      await service.installAndRestart(staged);
    } catch (e) {
      if (!mounted) return;
      if (dialogOpen) {
        Navigator.of(context).pop();
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${t('update_error')}: $e')),
      );
    }
  }

  List<Widget> get _pages => [
        DashboardTab(
          traderService: widget.traderService,
          showMarketIndicators: widget.enableExternalEffects,
        ),
        SettingsTab(
          settings: widget.settings,
          traderService: widget.traderService,
          onSaved: () => setState(() {}),
        ),
        LogsTab(logService: widget.logService),
        const SponsorsTab(),
        const AboutTab(),
      ];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= _desktopBreak;
        return isDesktop ? _desktopLayout() : _mobileLayout();
      },
    );
  }

  // ── Mobile: bottom navigation bar ─────────────────────────────────────────

  Widget _mobileLayout() {
    return Scaffold(
      body: Column(children: [
        Expanded(child: IndexedStack(index: _tab, children: _pages)),
        if (widget.showSponsorBanner) const SponsorBanner(),
      ]),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _tab,
        onTap: _onTab,
        items: _navItems(),
      ),
    );
  }

  // ── Desktop: sidebar (NavigationRail) ──────────────────────────────────────

  Widget _desktopLayout() {
    return Scaffold(
      body: Row(children: [
        // Sidebar
        Container(
          width: 200,
          color: AppColors.panel,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Logo header
              Container(
                height: 64,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                alignment: Alignment.centerLeft,
                child: const Text(
                  '⚡ LN Markets',
                  style: TextStyle(
                      color: AppColors.orange,
                      fontSize: 16,
                      fontWeight: FontWeight.bold),
                ),
              ),
              const Divider(color: AppColors.divider, height: 1),
              const SizedBox(height: 8),
              // Nav items
              ..._sidebarItems(),
              const Spacer(),
              const Divider(color: AppColors.divider, height: 1),
              // Sponsor banner in sidebar footer
              if (widget.showSponsorBanner) const SponsorBanner(),
              const SizedBox(height: 8),
            ],
          ),
        ),

        const VerticalDivider(width: 1, color: AppColors.divider),

        // Content
        Expanded(
          child: IndexedStack(index: _tab, children: _pages),
        ),
      ]),
    );
  }

  List<Widget> _sidebarItems() {
    final labels = [
      t('nav_dashboard'),
      t('nav_settings'),
      t('nav_logs'),
      t('nav_sponsors'),
      t('nav_about'),
    ];
    final icons = [
      [Icons.dashboard_outlined, Icons.dashboard],
      [Icons.settings_outlined, Icons.settings],
      [Icons.list_alt_outlined, Icons.list_alt],
      [Icons.handshake_outlined, Icons.handshake],
      [Icons.info_outline, Icons.info],
    ];

    return List.generate(labels.length, (i) {
      final active = _tab == i;
      return InkWell(
        onTap: () => _onTab(i),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: active
                ? AppColors.orange.withValues(alpha: 0.12)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(children: [
            Icon(
              active ? icons[i][1] : icons[i][0],
              size: 20,
              color: active ? AppColors.orange : AppColors.textMuted,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                labels[i],
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: active ? FontWeight.bold : FontWeight.normal,
                    color: active ? AppColors.orange : AppColors.textMuted),
              ),
            ),
          ]),
        ),
      );
    });
  }

  List<BottomNavigationBarItem> _navItems() => [
        BottomNavigationBarItem(
          icon: const Icon(Icons.dashboard_outlined),
          activeIcon: const Icon(Icons.dashboard),
          label: t('nav_dashboard'),
        ),
        BottomNavigationBarItem(
          icon: const Icon(Icons.settings_outlined),
          activeIcon: const Icon(Icons.settings),
          label: t('nav_settings'),
        ),
        BottomNavigationBarItem(
          icon: const Icon(Icons.list_alt_outlined),
          activeIcon: const Icon(Icons.list_alt),
          label: t('nav_logs'),
        ),
        BottomNavigationBarItem(
          icon: const Icon(Icons.handshake_outlined),
          activeIcon: const Icon(Icons.handshake),
          label: t('nav_sponsors'),
        ),
        BottomNavigationBarItem(
          icon: const Icon(Icons.info_outline),
          activeIcon: const Icon(Icons.info),
          label: t('nav_about'),
        ),
      ];
}
