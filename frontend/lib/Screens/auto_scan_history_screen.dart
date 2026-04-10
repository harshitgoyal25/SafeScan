import 'package:flutter/material.dart';

import '../models/sms_scan_result.dart';
import '../services/auto_scan_history_service.dart';

class AutoScanHistoryScreen extends StatefulWidget {
  const AutoScanHistoryScreen({super.key});

  @override
  State<AutoScanHistoryScreen> createState() => _AutoScanHistoryScreenState();
}

class _AutoScanHistoryScreenState extends State<AutoScanHistoryScreen> {
  late Future<List<SmsScanResult>> _historyFuture;

  @override
  void initState() {
    super.initState();
    _historyFuture = AutoScanHistoryService.getHistory();
  }

  Future<void> _reload() async {
    setState(() {
      _historyFuture = AutoScanHistoryService.getHistory();
    });
  }

  Future<void> _clearHistory() async {
    await AutoScanHistoryService.clearHistory();
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF060F1A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Auto Scan History'),
        actions: [
          IconButton(
            onPressed: _clearHistory,
            icon: const Icon(Icons.delete_outline_rounded),
            tooltip: 'Clear history',
          ),
        ],
      ),
      body: FutureBuilder<List<SmsScanResult>>(
        future: _historyFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final history = snapshot.data ?? const <SmsScanResult>[];
          if (history.isEmpty) {
            return Center(
              child: Text(
                'No automatic scan history yet.',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.65)),
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: _reload,
            child: ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 20),
              itemCount: history.length,
              itemBuilder: (context, index) {
                final item = history[index];
                return _historyCard(item);
              },
            ),
          );
        },
      ),
    );
  }

  Widget _historyCard(SmsScanResult result) {
    final suspicious = result.status == 'suspicious' || result.status == 'danger';
    final accent = suspicious ? Colors.orangeAccent : Colors.greenAccent;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1F2D),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                suspicious ? Icons.warning_amber_rounded : Icons.verified_rounded,
                color: accent,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  result.status.toUpperCase(),
                  style: TextStyle(
                    color: accent,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                _formatTime(result.timestamp),
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.65),
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _row('Source App', result.sourceApp),
          _row('SMS Status', result.smsStatus),
          _row('Sender', result.sender),
          _row('Message', result.smsBody),
          if (result.urlVerdicts.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'URL Verdicts',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.75),
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 6),
            ...result.urlVerdicts.map(
              (verdict) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '${verdict.status.toUpperCase()}  |  ${verdict.url}',
                  style: TextStyle(
                    color: verdict.isSafe ? Colors.greenAccent : Colors.orangeAccent,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(color: Colors.white, fontSize: 12.5),
          children: [
            TextSpan(
              text: '$label: ',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontWeight: FontWeight.w600,
              ),
            ),
            TextSpan(text: value.isEmpty ? '-' : value),
          ],
        ),
      ),
    );
  }

  String _formatTime(int timestamp) {
    final dt = DateTime.fromMillisecondsSinceEpoch(timestamp).toLocal();
    final month = dt.month.toString().padLeft(2, '0');
    final day = dt.day.toString().padLeft(2, '0');
    final hour = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    return '${dt.year}-$month-$day $hour:$min';
  }
}
