import 'package:flutter/material.dart';
import '../services/auto_scan_controller.dart';
import '../widgets/security_tool_card.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _autoProtectionEnabled = false;
  bool _isLoadingToggle = true;
  bool _hasNotificationAccess = false;

  @override
  void initState() {
    super.initState();
    _loadAutoProtectionState();
  }

  Future<void> _loadAutoProtectionState() async {
    final enabled = await AutoScanController.isEnabled();
    final access = await AutoScanController.isNotificationAccessEnabled();
    if (!mounted) return;
    setState(() {
      _autoProtectionEnabled = enabled;
      _hasNotificationAccess = access;
      _isLoadingToggle = false;
    });
  }

  Future<void> _onToggleAutoProtection(bool value) async {
    setState(() => _isLoadingToggle = true);
    try {
      await AutoScanController.toggle(value);
      final access = await AutoScanController.isNotificationAccessEnabled();
      if (!mounted) return;
      setState(() {
        _autoProtectionEnabled = value;
        _hasNotificationAccess = access;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: Colors.redAccent,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoadingToggle = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final subtitle = _autoProtectionEnabled
        ? (_hasNotificationAccess
              ? 'SafeScan will scan incoming SMS and notification text automatically.'
              : 'Enabled, but notification access is still required in Android settings.')
        : 'Enable to auto-scan incoming SMS and app notifications.';

    return Scaffold(
      backgroundColor: const Color(0xFF060F1A),
      body: CustomScrollView(
        slivers: [
          // ---- HEADER ----
          SliverAppBar(
            expandedHeight: 80,
            pinned: true,
            backgroundColor: const Color(0xFF060F1A),
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            flexibleSpace: FlexibleSpaceBar(
              titlePadding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 14,
              ),
              title: Row(
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text(
                        "SafeScan",
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: -0.5,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // ---- SECTION TITLE ----
                const Text(
                  "Security Tools",
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  "Choose what you want to scan",
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.white.withValues(alpha: 0.45),
                  ),
                ),
                const SizedBox(height: 16),

                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0D1F2D),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.shield_rounded,
                            color: Color(0xFF26C6DA),
                            size: 20,
                          ),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Text(
                              'Auto Protection',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                              ),
                            ),
                          ),
                          Switch.adaptive(
                            value: _autoProtectionEnabled,
                            onChanged: _isLoadingToggle
                                ? null
                                : _onToggleAutoProtection,
                            activeThumbColor: const Color(0xFF26C6DA),
                            activeTrackColor: const Color(
                              0xFF26C6DA,
                            ).withValues(alpha: 0.45),
                          ),
                        ],
                      ),
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.65),
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () {
                            Navigator.pushNamed(context, '/auto-history');
                          },
                          icon: const Icon(Icons.history_rounded, size: 18),
                          label: const Text('View Auto Scan History'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF26C6DA),
                            side: BorderSide(
                              color: const Color(
                                0xFF26C6DA,
                              ).withValues(alpha: 0.4),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // ---- TOOL GRID ----
                GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: 2,
                  crossAxisSpacing: 14,
                  mainAxisSpacing: 14,
                  childAspectRatio: 1.0,
                  children: const [
                    SecurityToolCard(
                      icon: Icons.link_rounded,
                      title: "URL Scan",
                      scanType: "url",
                      accentColor: Color(0xFF26C6DA),
                    ),
                    SecurityToolCard(
                      icon: Icons.sms_rounded,
                      title: "SMS Scan",
                      scanType: "sms",
                      accentColor: Color(0xFFAB47BC),
                    ),
                    SecurityToolCard(
                      icon: Icons.android_rounded,
                      title: "APK Scan",
                      scanType: "apk",
                      accentColor: Color(0xFFFFB74D),
                    ),
                  ],
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}
