import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'dart:io';
import 'services/scan_api_service.dart';
import 'services/auto_scan_controller.dart';
import 'services/auto_scan_history_service.dart';
import 'Screens/sms_result_screen.dart';
import 'Screens/home_screen.dart';
import 'Screens/scan_screen.dart';
import 'Screens/auto_scan_history_screen.dart';
import 'models/sms_scan_result.dart';

void main() {
  runApp(const SafeScanApp());
}

class SafeScanApp extends StatefulWidget {
  const SafeScanApp({super.key});

  @override
  State<SafeScanApp> createState() => _SafeScanAppState();
}

class _SafeScanAppState extends State<SafeScanApp> {
  static const MethodChannel _autoSmsChannel = MethodChannel(
    'com.example.safescan/auto_sms',
  );
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  final ScanApiService _scanApiService = ScanApiService();

  SmsScanResult? _pendingResult;
  bool _isProcessingIncomingApk = false;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) {
      _autoSmsChannel.setMethodCallHandler(_onNativeMethodCall);
    }
    _initializeAutoSmsMonitoring();
  }

  Future<void> _onNativeMethodCall(MethodCall call) async {
    if (call.method == 'onSmsScanResult') {
      final payload = call.arguments;
      if (payload is! Map<Object?, Object?> || !mounted) {
        return;
      }

      final result = SmsScanResult.fromMap(payload);
      await AutoScanHistoryService.addEntry(result);
      setState(() {
        _pendingResult = result;
      });
      _navigatorKey.currentState?.pushNamed('/sms-result', arguments: result);
      return;
    }

    if (call.method == 'onIncomingApkForScan') {
      final payload = call.arguments;
      if (payload is! Map<Object?, Object?> || !mounted) {
        return;
      }

      await _handleIncomingApkScan(payload);
    }
  }

  Future<void> _initializeAutoSmsMonitoring() async {
    if (kIsWeb) {
      return;
    }

    await _syncNativeBackendCandidates();
    await AutoScanController.initOnStartup();
    await _loadNotificationTapResult();
    await _loadIncomingApkScanRequest();
  }

  Future<void> _syncNativeBackendCandidates() async {
    try {
      await _autoSmsChannel.invokeMethod('setBackendCandidates', {
        'candidates': ScanApiService.backendCandidates,
      });
    } catch (_) {
      // Keep defaults on native side when channel update is unavailable.
    }
  }

  Future<void> _loadNotificationTapResult() async {
    try {
      final dynamic payload = await _autoSmsChannel.invokeMethod<dynamic>(
        'getInitialSmsScanResult',
      );
      if (payload is Map<Object?, Object?> && mounted) {
        final result = SmsScanResult.fromMap(payload);
        await AutoScanHistoryService.addEntry(result);
        setState(() {
          _pendingResult = result;
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _navigatorKey.currentState?.pushNamed(
            '/sms-result',
            arguments: result,
          );
        });
      }
    } catch (_) {
      // Ignore channel failures; app still supports manual scanning.
    }
  }

  Future<void> _loadIncomingApkScanRequest() async {
    try {
      final dynamic payload = await _autoSmsChannel.invokeMethod<dynamic>(
        'getInitialIncomingApkScanRequest',
      );

      if (payload is Map<Object?, Object?> && mounted) {
        await _handleIncomingApkScan(payload);
      }
    } catch (_) {
      // Ignore channel failures; manual APK scan remains available.
    }
  }

  Future<void> _handleIncomingApkScan(Map<Object?, Object?> payload) async {
    if (_isProcessingIncomingApk) {
      return;
    }

    final uri = (payload['uri'] as String?)?.trim() ?? '';
    final displayName =
        (payload['displayName'] as String?)?.trim().isNotEmpty == true
        ? payload['displayName'] as String
        : 'Incoming APK';
    final int timestamp = (payload['timestamp'] as num?)?.toInt() ??
        DateTime.now().millisecondsSinceEpoch;

    if (uri.isEmpty) {
      return;
    }

    _isProcessingIncomingApk = true;
    var loadingShown = false;
    String localApkPath = '';

    try {
      final loadingContext = _navigatorKey.currentContext;
      if (loadingContext != null) {
        loadingShown = true;
        showDialog<void>(
          context: loadingContext,
          barrierDismissible: false,
          builder: (_) {
            return AlertDialog(
              backgroundColor: const Color(0xFF0D1F2D),
              title: const Text('Checking APK Safety'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    displayName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 12),
                  const LinearProgressIndicator(),
                  const SizedBox(height: 8),
                  const Text('SafeScan is analyzing this APK before install.'),
                ],
              ),
            );
          },
        );
      }

      localApkPath =
          await _autoSmsChannel.invokeMethod<String>('copyApkUriToCache', {
            'uri': uri,
          }) ??
          '';
      if (localApkPath.isEmpty) {
        throw Exception('Could not open incoming APK for safety scan.');
      }

      final scanStatus = await _scanApiService.scanApk(localApkPath);
      final historyEntry = SmsScanResult(
        status: scanStatus,
        smsStatus: scanStatus,
        smsBody: 'APK file: $displayName',
        sender: 'Package Installer Layer',
        timestamp: timestamp,
        urls: const <String>[],
        urlStatuses: const <String>[],
        sourceApp: 'android.packageinstaller',
        sourceType: 'apk_install_gate',
      );
      await AutoScanHistoryService.addEntry(historyEntry);

      if (loadingShown && mounted) {
        _navigatorKey.currentState?.pop();
        loadingShown = false;
      }

      if (scanStatus == 'safe') {
        final installed =
            await _autoSmsChannel.invokeMethod<bool>('installApkFromUri', {
              'uri': uri,
            }) ??
            false;

        if (!installed && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'APK looks safe, but installer could not be launched.',
              ),
              backgroundColor: Colors.orangeAccent,
            ),
          );
        }
      } else {
        if (mounted) {
          showDialog<void>(
            context: context,
            builder: (dialogContext) {
              return AlertDialog(
                backgroundColor: const Color(0xFF0D1F2D),
                title: const Text('Installation Blocked'),
                content: Text(
                  'SafeScan flagged this APK as $scanStatus, so installation was blocked.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    child: const Text('OK'),
                  ),
                ],
              );
            },
          );
        }
      }
    } catch (e) {
      if (loadingShown && mounted) {
        _navigatorKey.currentState?.pop();
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('APK gate failed: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (localApkPath.isNotEmpty) {
        try {
          final file = File(localApkPath);
          if (await file.exists()) {
            await file.delete();
          }
        } catch (_) {
          // Best effort cleanup only.
        }
      }
      _isProcessingIncomingApk = false;
    }
  }

  Route<dynamic> _onGenerateRoute(RouteSettings settings) {
    if (settings.name == '/sms-result') {
      final SmsScanResult? result =
          (settings.arguments as SmsScanResult?) ?? _pendingResult;
      if (result != null) {
        _pendingResult = null;
        return MaterialPageRoute(
          builder: (_) => SmsResultScreen(result: result),
          settings: settings,
        );
      }
      return MaterialPageRoute(builder: (_) => const HomeScreen());
    }

    if (settings.name == '/scan') {
      return MaterialPageRoute(
        builder: (_) => const ScanScreen(),
        settings: settings,
      );
    }

    if (settings.name == '/auto-history') {
      return MaterialPageRoute(
        builder: (_) => const AutoScanHistoryScreen(),
        settings: settings,
      );
    }

    return MaterialPageRoute(builder: (_) => const HomeScreen());
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigatorKey,
      title: 'SafeScan',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF060F1A),
        fontFamily: 'Inter',
      ),
      initialRoute: '/',
      onGenerateRoute: _onGenerateRoute,
    );
  }
}
