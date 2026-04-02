import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'services/scan_api_service.dart';
import 'screens/home_screen.dart';
import 'screens/scan_screen.dart';
import 'Screens/sms_result_screen.dart';
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

  SmsScanResult? _pendingResult;

  @override
  void initState() {
    super.initState();
    _autoSmsChannel.setMethodCallHandler(_onNativeMethodCall);
    _initializeAutoSmsMonitoring();
  }

  Future<void> _onNativeMethodCall(MethodCall call) async {
    if (call.method != 'onSmsScanResult') {
      return;
    }

    final payload = call.arguments;
    if (payload is! Map<Object?, Object?> || !mounted) {
      return;
    }

    final result = SmsScanResult.fromMap(payload);
    setState(() {
      _pendingResult = result;
    });
    _navigatorKey.currentState?.pushNamed('/sms-result', arguments: result);
  }

  Future<void> _initializeAutoSmsMonitoring() async {
    await _syncNativeBackendCandidates();
    await _requestAutoSmsPermissions();
    await _loadNotificationTapResult();
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

  Future<void> _requestAutoSmsPermissions() async {
    await Permission.sms.request();
    await Permission.notification.request();
  }

  Future<void> _loadNotificationTapResult() async {
    try {
      final dynamic payload = await _autoSmsChannel.invokeMethod<dynamic>(
        'getInitialSmsScanResult',
      );
      if (payload is Map<Object?, Object?> && mounted) {
        final result = SmsScanResult.fromMap(payload);
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
