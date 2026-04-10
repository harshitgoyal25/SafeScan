import 'package:flutter/material.dart';

class SecurityToolCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String scanType;
  final Color accentColor;

  const SecurityToolCard({
    super.key,
    required this.icon,
    required this.title,
    required this.scanType,
    this.accentColor = const Color(0xFF26C6DA),
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        if (scanType != "history") {
          Navigator.pushNamed(context, '/scan', arguments: scanType);
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              const Color(0xFF102A3B),
              const Color(0xFF0B1E2D),
            ],
          ),
          border: Border.all(
            color: accentColor.withValues(alpha: 0.25),
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: accentColor.withValues(alpha: 0.08),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 28, color: accentColor),
            ),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.white,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
