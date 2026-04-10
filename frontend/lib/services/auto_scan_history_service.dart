import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/sms_scan_result.dart';

class AutoScanHistoryService {
  static const String _storageKey = 'auto_scan_history_v1';
  static const int _maxEntries = 150;

  static Future<void> addEntry(SmsScanResult result) async {
    final prefs = await SharedPreferences.getInstance();
    final records = prefs.getStringList(_storageKey) ?? <String>[];

    final eventId = _eventId(result);
    final alreadyExists = records.any((encoded) {
      try {
        final decoded = jsonDecode(encoded);
        if (decoded is! Map<String, dynamic>) return false;
        return decoded['eventId'] == eventId;
      } catch (_) {
        return false;
      }
    });

    if (alreadyExists) {
      return;
    }

    final payload = result.toStorageMap()..['eventId'] = eventId;
    records.insert(0, jsonEncode(payload));

    if (records.length > _maxEntries) {
      records.removeRange(_maxEntries, records.length);
    }

    await prefs.setStringList(_storageKey, records);
  }

  static Future<List<SmsScanResult>> getHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final records = prefs.getStringList(_storageKey) ?? <String>[];

    final parsed = <SmsScanResult>[];
    for (final encoded in records) {
      try {
        final decoded = jsonDecode(encoded);
        if (decoded is Map<String, dynamic>) {
          parsed.add(SmsScanResult.fromStorageMap(decoded));
        }
      } catch (_) {
        // Skip malformed entries.
      }
    }

    parsed.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return parsed;
  }

  static Future<void> clearHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKey);
  }

  static String _eventId(SmsScanResult result) {
    return [
      result.timestamp,
      result.sourceApp,
      result.sender,
      result.smsBody.hashCode,
      result.status,
    ].join('|');
  }
}
