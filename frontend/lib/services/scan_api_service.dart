import 'dart:convert';

import 'package:http/http.dart' as http;

class ScanApiService {
  ScanApiService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static List<String> get backendCandidates {
    const String configuredUrl = String.fromEnvironment('BACKEND_URL');
    if (configuredUrl.isNotEmpty) {
      return [configuredUrl];
    }

    // 10.0.2.2 works on emulator; 127.0.0.1 works on physical devices with adb reverse.
    return const ['http://10.0.2.2:8000', 'http://127.0.0.1:8000'];
  }

  Future<String> scanUrl(String input) async {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return 'safe';

    return _scanWithFallback(path: '/scan/url', payload: {'url': trimmed});
  }

  Future<String> scanSms(String input) async {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return 'safe';

    return _scanWithFallback(path: '/scan/sms', payload: {'sms': trimmed});
  }

  Future<String> scanApk(dynamic file) async {
    // Expected 'file' to be file_picker's PlatformFile but used dynamic to avoid coupling
    Object? lastError;
    for (final baseUrl in backendCandidates) {
      try {
        final uri = Uri.parse('$baseUrl/scan/apk');
        final request = http.MultipartRequest('POST', uri);

        if (file.bytes != null) {
          // Web typically provides bytes
          request.files.add(http.MultipartFile.fromBytes('file', file.bytes as List<int>, filename: file.name));
        } else if (file.path != null) {
          // Mobile provides path
          request.files.add(await http.MultipartFile.fromPath('file', file.path as String));
        } else {
          throw Exception('No file data available');
        }

        final streamedResponse = await _client.send(request);
        final response = await http.Response.fromStream(streamedResponse);

        if (response.statusCode == 200) {
          return jsonDecode(response.body)['status'] as String;
        }
        lastError = Exception('Status ${response.statusCode} from $baseUrl');
      } catch (e) {
        lastError = e;
      }
    }

    throw Exception('Failed to reach backend for APK scan: $lastError');
  }

  Future<String> _scanWithFallback({
    required String path,
    required Map<String, String> payload,
  }) async {
    Object? lastError;
    for (final baseUrl in backendCandidates) {
      try {
        final response = await _client.post(
          Uri.parse('$baseUrl$path'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(payload),
        );

        if (response.statusCode == 200) {
          return jsonDecode(response.body)['status'] as String;
        }
        lastError = Exception('Status ${response.statusCode} from $baseUrl');
      } catch (e) {
        lastError = e;
      }
    }

    throw Exception('Failed to reach backend on any candidate URL: $lastError');
  }
}
