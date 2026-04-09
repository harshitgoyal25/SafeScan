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

    return const [
      'http://10.0.2.2:8000',
      'http://127.0.0.1:8000',
      'http://10.0.2.2:8001',
      'http://127.0.0.1:8001',
    ];
  }

  Future<String> scanUrl(String input) async {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return 'safe';

    return _scanJsonWithFallback(path: '/scan/url', payload: {'url': trimmed});
  }

  Future<String> scanSms(String input) async {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return 'safe';

    return _scanJsonWithFallback(path: '/scan/sms', payload: {'sms': trimmed});
  }

  Future<String> scanApk(String apkPath) async {
    final trimmed = apkPath.trim();
    if (trimmed.isEmpty) return 'safe';

    return _scanMultipartWithFallback(
      path: '/scan/apk',
      fileFieldName: 'file',
      filePath: trimmed,
    );
  }

  Future<String> _scanJsonWithFallback({
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
          return _extractStatus(response.body);
        }
        lastError = Exception('Status ${response.statusCode} from $baseUrl');
      } catch (e) {
        lastError = e;
      }
    }

    throw Exception('Failed to reach backend on any candidate URL: $lastError');
  }

  Future<String> _scanMultipartWithFallback({
    required String path,
    required String fileFieldName,
    required String filePath,
  }) async {
    Object? lastError;
    for (final baseUrl in backendCandidates) {
      try {
        final request = http.MultipartRequest(
          'POST',
          Uri.parse('$baseUrl$path'),
        );
        request.files.add(
          await http.MultipartFile.fromPath(fileFieldName, filePath),
        );

        final streamedResponse = await _client.send(request);
        final response = await http.Response.fromStream(streamedResponse);
        if (response.statusCode == 200) {
          return _extractStatus(response.body);
        }
        lastError = Exception('Status ${response.statusCode} from $baseUrl');
      } catch (e) {
        lastError = e;
      }
    }

    throw Exception('Failed to reach backend on any candidate URL: $lastError');
  }

  String _extractStatus(String responseBody) {
    final decoded = jsonDecode(responseBody);
    if (decoded is Map<String, dynamic> && decoded['status'] is String) {
      return decoded['status'] as String;
    }
    throw Exception('Backend response did not include a status field');
  }
}
