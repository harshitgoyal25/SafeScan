import 'package:flutter/material.dart';

import '../models/sms_scan_result.dart';

class SmsResultScreen extends StatelessWidget {
  const SmsResultScreen({required this.result, super.key});

  final SmsScanResult result;

  @override
  Widget build(BuildContext context) {
    final isSuspicious =
        result.status == 'suspicious' || result.status == 'danger';
    final Color color = isSuspicious ? Colors.orangeAccent : Colors.greenAccent;
    final IconData icon = isSuspicious
        ? Icons.warning_amber_rounded
        : Icons.verified_rounded;
    final String title = isSuspicious ? 'Suspicious SMS' : 'SMS Looks Safe';
    final String subtitle = isSuspicious
        ? 'Avoid clicking links or sharing OTPs before verification.'
        : 'No immediate scam indicators were detected in this SMS.';

    return Scaffold(
      backgroundColor: const Color(0xFF060F1A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Auto SMS Scan Result'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: color.withValues(alpha: 0.5),
                  width: 1.5,
                ),
                gradient: LinearGradient(
                  colors: isSuspicious
                      ? [const Color(0xFF332200), const Color(0xFF1A1200)]
                      : [const Color(0xFF00331A), const Color(0xFF001A0D)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Row(
                children: [
                  Icon(icon, color: color, size: 30),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            color: color,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          subtitle,
                          style: TextStyle(color: color.withValues(alpha: 0.8)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            _detailCard('Sender', result.sender),
            const SizedBox(height: 12),
            _detailCard('SMS', result.smsBody),
          ],
        ),
      ),
    );
  }

  Widget _detailCard(String label, String value) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1F2D),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Colors.white70,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            value.isEmpty ? '-' : value,
            style: const TextStyle(color: Colors.white, fontSize: 14),
          ),
        ],
      ),
    );
  }
}
