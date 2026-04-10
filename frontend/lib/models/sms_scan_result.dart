class SmsScanResult {
  const SmsScanResult({
    required this.status,
    required this.smsStatus,
    required this.smsBody,
    required this.sender,
    required this.timestamp,
    required this.urls,
    required this.urlStatuses,
    required this.sourceApp,
    required this.sourceType,
  });

  final String status;
  final String smsStatus;
  final String smsBody;
  final String sender;
  final int timestamp;
  final List<String> urls;
  final List<String> urlStatuses;
  final String sourceApp;
  final String sourceType;

  bool get isSafe => status == 'safe';

  List<UrlVerdict> get urlVerdicts {
    final int count = urls.length < urlStatuses.length
        ? urls.length
        : urlStatuses.length;
    return List<UrlVerdict>.generate(
      count,
      (index) => UrlVerdict(url: urls[index], status: urlStatuses[index]),
      growable: false,
    );
  }

  factory SmsScanResult.fromMap(Map<Object?, Object?> map) {
    final Object? timestampRaw = map['timestamp'];
    final List<String> parsedUrls =
        ((map['urls'] as List?) ?? const <Object?>[])
            .whereType<String>()
            .toList(growable: false);
    final List<String> parsedUrlStatuses =
        ((map['urlStatuses'] as List?) ?? const <Object?>[])
            .whereType<String>()
            .toList(growable: false);

    return SmsScanResult(
      status: (map['status'] as String?) ?? 'safe',
      smsStatus: (map['smsStatus'] as String?) ?? 'safe',
      smsBody: (map['smsBody'] as String?) ?? '',
      sender: (map['sender'] as String?) ?? 'Unknown Sender',
      timestamp: timestampRaw is num ? timestampRaw.toInt() : 0,
      urls: parsedUrls,
      urlStatuses: parsedUrlStatuses,
      sourceApp: (map['sourceApp'] as String?) ?? 'android.sms',
      sourceType: (map['sourceType'] as String?) ?? 'sms_broadcast',
    );
  }

  Map<String, dynamic> toStorageMap() {
    return {
      'status': status,
      'smsStatus': smsStatus,
      'smsBody': smsBody,
      'sender': sender,
      'timestamp': timestamp,
      'urls': urls,
      'urlStatuses': urlStatuses,
      'sourceApp': sourceApp,
      'sourceType': sourceType,
    };
  }

  factory SmsScanResult.fromStorageMap(Map<String, dynamic> map) {
    return SmsScanResult(
      status: (map['status'] as String?) ?? 'safe',
      smsStatus: (map['smsStatus'] as String?) ?? 'safe',
      smsBody: (map['smsBody'] as String?) ?? '',
      sender: (map['sender'] as String?) ?? 'Unknown Sender',
      timestamp: (map['timestamp'] as num?)?.toInt() ?? 0,
      urls: ((map['urls'] as List?) ?? const <Object?>[])
          .whereType<String>()
          .toList(growable: false),
      urlStatuses: ((map['urlStatuses'] as List?) ?? const <Object?>[])
          .whereType<String>()
          .toList(growable: false),
      sourceApp: (map['sourceApp'] as String?) ?? 'android.sms',
      sourceType: (map['sourceType'] as String?) ?? 'sms_broadcast',
    );
  }
}

class UrlVerdict {
  const UrlVerdict({required this.url, required this.status});

  final String url;
  final String status;

  bool get isSafe => status == 'safe';
}
