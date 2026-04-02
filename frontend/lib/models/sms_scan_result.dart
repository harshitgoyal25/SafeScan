class SmsScanResult {
  const SmsScanResult({
    required this.status,
    required this.smsBody,
    required this.sender,
    required this.timestamp,
  });

  final String status;
  final String smsBody;
  final String sender;
  final int timestamp;

  bool get isSafe => status == 'safe';

  factory SmsScanResult.fromMap(Map<Object?, Object?> map) {
    final Object? timestampRaw = map['timestamp'];

    return SmsScanResult(
      status: (map['status'] as String?) ?? 'safe',
      smsBody: (map['smsBody'] as String?) ?? '',
      sender: (map['sender'] as String?) ?? 'Unknown Sender',
      timestamp: timestampRaw is num ? timestampRaw.toInt() : 0,
    );
  }
}
