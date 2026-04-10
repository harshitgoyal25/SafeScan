import 'package:flutter/material.dart';
import 'dart:ui';

class SafeScanShield extends StatelessWidget {
  final bool isProtected;

  const SafeScanShield({
    super.key,
    required this.isProtected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 280, // Reduced height since toggle is gone
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(32),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // GLOW RADIANCE
          Positioned(
            top: 20,
            child: Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: (isProtected ? const Color(0xFF38BDF8) : const Color(0xFFEF4444)).withValues(alpha: 0.12),
                    blurRadius: 80,
                    spreadRadius: 30,
                  ),
                ],
              ),
            ),
          ),

          // GLASS SHIELD
          ClipRRect(
            borderRadius: BorderRadius.circular(32),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Container(
                width: 240,
                height: 240,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.03),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.08),
                    width: 1.2,
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      isProtected ? Icons.shield_rounded : Icons.report_problem_rounded,
                      size: 70,
                      color: isProtected ? const Color(0xFF38BDF8) : const Color(0xFFEF4444),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      isProtected ? "PROTECTED" : "THREATS!",
                      style: TextStyle(
                        color: isProtected ? const Color(0xFF38BDF8) : const Color(0xFFEF4444),
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
