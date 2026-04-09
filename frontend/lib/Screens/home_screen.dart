import 'package:flutter/material.dart';
import '../widgets/security_tool_card.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
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
                    color: Colors.white.withOpacity(0.45),
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
