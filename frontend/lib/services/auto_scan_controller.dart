import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AutoScanController {
  static const _channel = MethodChannel('com.example.safescan/auto_sms');
  static const _storageKey = 'auto_sms_scan_enabled';

  static Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_storageKey) ?? false;
  }

  static Future<void> toggle(bool enable) async {
    if (enable) {
      // Request runtime permissions needed for SMS receiver and result notifications.
      final notificationStatus = await Permission.notification.request();
      if (notificationStatus != PermissionStatus.granted) {
        throw Exception(
          "Notification permission is required for auto-scanning.",
        );
      }

      final smsStatus = await Permission.sms.request();
      if (smsStatus != PermissionStatus.granted) {
        throw Exception(
          "SMS permission is required for automatic SMS scanning.",
        );
      }

      final accessGranted =
          await _channel.invokeMethod<bool>('startMonitor') ?? false;
      if (!accessGranted) {
        throw Exception(
          'Enable "Notification access" for SafeScan in Android settings.',
        );
      }
    } else {
      await _channel.invokeMethod('stopMonitor');
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_storageKey, enable);
  }

  static Future<void> initOnStartup() async {
    if (await isEnabled()) {
      try {
        await _channel.invokeMethod('startMonitor');
      } catch (e) {
        // Silently fail if permissions were revoked.
      }
    }
  }

  static Future<bool> isNotificationAccessEnabled() async {
    return await _channel.invokeMethod<bool>('isNotificationListenerEnabled') ??
        false;
  }
}
