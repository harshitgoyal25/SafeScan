import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../services/scan_api_service.dart';

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen>
    with SingleTickerProviderStateMixin {
  String scanType = 'url';
  final TextEditingController _textController = TextEditingController();
  final ScanApiService _scanApiService = ScanApiService();

  bool isScanning = false;
  double progress = 0.0;
  String? resultStatus;
  String? _selectedApkPath;
  String? _selectedApkName;

  AnimationController? _pulseController;
  Animation<double>? _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _textController.addListener(() => setState(() {}));
    _initAnimations();
  }

  void _initAnimations() {
    _pulseController ??= AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _pulseAnimation ??= Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _pulseController!, curve: Curves.easeInOut),
    );
  }

  @override
  void reassemble() {
    super.reassemble();
    _initAnimations();
  }

  @override
  void dispose() {
    _textController.dispose();
    _pulseController?.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final String? routeType =
        ModalRoute.of(context)?.settings.arguments as String?;
    if (routeType == 'url' || routeType == 'sms' || routeType == 'apk') {
      scanType = routeType!;
    } else {
      scanType = 'url';
    }
  }

  Future<void> _pickApkFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['apk'],
      allowMultiple: false,
      withData: false,
    );

    if (!mounted || result == null || result.files.isEmpty) {
      return;
    }

    final file = result.files.first;
    if (file.path == null || file.path!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not access the selected APK file.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    setState(() {
      _selectedApkPath = file.path;
      _selectedApkName = file.name;
      resultStatus = null;
      progress = 0;
    });
  }

  /* ---------------- SCAN LOGIC ---------------- */

  Future<void> startScan() async {
    if (scanType == 'apk' &&
        (_selectedApkPath == null || _selectedApkPath!.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Pick an APK file first.'),
          backgroundColor: Colors.orangeAccent,
        ),
      );
      return;
    }

    setState(() {
      isScanning = true;
      progress = 0;
      resultStatus = null;
    });

    final progressTimer = Timer.periodic(const Duration(milliseconds: 100), (
      timer,
    ) {
      if (progress < 0.9) {
        setState(() => progress += 0.05);
      }
    });

    try {
      final finalResult = await _performRealScan();
      progressTimer.cancel();
      setState(() {
        progress = 1.0;
        isScanning = false;
        resultStatus = finalResult;
      });
    } catch (e) {
      progressTimer.cancel();
      setState(() {
        progress = 1.0;
        isScanning = false;
        resultStatus = 'safe';
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.redAccent),
      );
    }
  }

  Future<String> _performRealScan() async {
    if (scanType == 'apk') {
      return _scanApiService.scanApk(_selectedApkPath!);
    }
    if (scanType == 'sms') {
      return _scanApiService.scanSms(_textController.text);
    }
    return _scanApiService.scanUrl(_textController.text);
  }

  /* ---------------- UI ---------------- */

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF060F1A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        leading: GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Container(
            margin: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF102A3B),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.arrow_back_ios_new_rounded,
              size: 16,
              color: Colors.white70,
            ),
          ),
        ),
        title: Text(
          _title(),
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 17,
            letterSpacing: -0.3,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        child: Column(
          children: [
            const SizedBox(height: 8),
            _scanCircle(),
            const SizedBox(height: 28),
            _instructionText(),
            const SizedBox(height: 14),
            _inputSection(),
            const SizedBox(height: 20),
            _scanButton(),
            const SizedBox(height: 24),
            if (resultStatus != null) _resultCard(),
          ],
        ),
      ),
    );
  }

  /* ---------------- HELPERS ---------------- */

  String _title() {
    switch (scanType) {
      case 'url':
        return 'URL Scanner';
      case 'sms':
        return 'SMS Scanner';
      case 'apk':
        return 'APK Scanner';
      default:
        return 'URL Scanner';
    }
  }

  Color _accentColor() {
    switch (scanType) {
      case 'url':
        return const Color(0xFF26C6DA);
      case 'sms':
        return const Color(0xFFAB47BC);
      case 'apk':
        return const Color(0xFFFFB74D);
      default:
        return const Color(0xFF26C6DA);
    }
  }

  IconData _scanIcon() {
    switch (scanType) {
      case 'url':
        return Icons.link_rounded;
      case 'sms':
        return Icons.sms_rounded;
      case 'apk':
        return Icons.android_rounded;
      default:
        return Icons.link_rounded;
    }
  }

  Widget _instructionText() {
    final String hint = switch (scanType) {
      'sms' => 'Paste the suspicious SMS message below',
      'apk' => 'Choose an APK file and scan it for malware indicators',
      _ => 'Enter the URL you want to analyze',
    };

    return Text(
      hint,
      textAlign: TextAlign.center,
      style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 13.5),
    );
  }

  Widget _inputSection() {
    if (scanType == 'apk') {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF0D1F2D),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: _accentColor().withOpacity(0.3),
            width: 1.2,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'APK file',
              style: TextStyle(
                color: Colors.white.withOpacity(0.65),
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.4,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              _selectedApkName ?? 'No APK selected yet',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _selectedApkPath ??
                  'Tap below to choose a file from device storage',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white.withOpacity(0.35),
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: isScanning ? null : _pickApkFile,
                style: OutlinedButton.styleFrom(
                  foregroundColor: _accentColor(),
                  side: BorderSide(color: _accentColor().withOpacity(0.5)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                icon: const Icon(Icons.upload_file_rounded, size: 18),
                label: Text(
                  _selectedApkPath == null ? 'Choose APK' : 'Change APK',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0D1F2D),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _accentColor().withOpacity(0.3), width: 1.2),
      ),
      child: TextField(
        controller: _textController,
        maxLines: scanType == 'sms' ? 5 : 1,
        style: const TextStyle(color: Colors.white, fontSize: 14),
        decoration: InputDecoration(
          hintText: scanType == 'sms'
              ? 'Paste SMS content here...'
              : 'https://example.com',
          hintStyle: TextStyle(color: Colors.white.withOpacity(0.25)),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.all(16),
          prefixIcon: Padding(
            padding: const EdgeInsets.only(left: 14, right: 6),
            child: Icon(
              _scanIcon(),
              size: 18,
              color: _accentColor().withOpacity(0.7),
            ),
          ),
          prefixIconConstraints: const BoxConstraints(minWidth: 44),
        ),
      ),
    );
  }

  Widget _scanButton() {
    final enabled = scanType == 'apk'
        ? _selectedApkPath != null && _selectedApkPath!.isNotEmpty
        : _textController.text.isNotEmpty;

    final accent = _accentColor();

    return SizedBox(
      width: double.infinity,
      height: 54,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: enabled
              ? LinearGradient(
                  colors: [accent, accent.withOpacity(0.7)],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                )
              : null,
          color: enabled ? null : const Color(0xFF102A3B),
          boxShadow: enabled
              ? [
                  BoxShadow(
                    color: accent.withOpacity(0.35),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
                ]
              : null,
        ),
        child: ElevatedButton(
          onPressed: (!enabled || isScanning) ? null : startScan,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            foregroundColor: Colors.white,
            shadowColor: Colors.transparent,
            disabledBackgroundColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
          ),
          child: isScanning
              ? const SizedBox(
                  height: 22,
                  width: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: Colors.white,
                  ),
                )
              : Text(
                  scanType == 'apk'
                      ? (enabled ? 'Scan APK' : 'Choose an APK to scan')
                      : (enabled ? 'Start Scan' : 'Enter input to scan'),
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: enabled ? Colors.white : Colors.white38,
                  ),
                ),
        ),
      ),
    );
  }

  Widget _scanCircle() {
    final Color accent = resultStatus == 'danger'
        ? Colors.redAccent
        : resultStatus == 'suspicious'
        ? Colors.orangeAccent
        : resultStatus == 'safe'
        ? Colors.greenAccent
        : _accentColor();

    final String label = isScanning
        ? '${(progress * 100).toInt()}%'
        : resultStatus == 'danger'
        ? 'THREAT'
        : resultStatus == 'suspicious'
        ? 'WARN'
        : resultStatus == 'safe'
        ? 'SAFE'
        : 'READY';

    return ScaleTransition(
      scale: (isScanning || resultStatus == null)
          ? (_pulseAnimation ?? const AlwaysStoppedAnimation(1.0))
          : const AlwaysStoppedAnimation(1.0),
      child: SizedBox(
        height: 180,
        width: 180,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              height: 160,
              width: 160,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: accent.withOpacity(0.2),
                    blurRadius: 40,
                    spreadRadius: 10,
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 170,
              width: 170,
              child: CircularProgressIndicator(
                value: 1,
                strokeWidth: 8,
                color: accent.withOpacity(0.1),
              ),
            ),
            SizedBox(
              height: 170,
              width: 170,
              child: CircularProgressIndicator(
                value: isScanning
                    ? progress
                    : (resultStatus != null ? 1.0 : 0.0),
                strokeWidth: 8,
                backgroundColor: Colors.transparent,
                color: accent,
                strokeCap: StrokeCap.round,
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(_scanIcon(), color: accent, size: 30),
                const SizedBox(height: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: accent,
                    letterSpacing: 1.5,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _resultCard() {
    Color color;
    String title;
    String subtitle;
    IconData icon;
    List<Color> gradColors;

    switch (resultStatus) {
      case 'danger':
        color = Colors.redAccent;
        title = 'Threat Detected';
        subtitle = 'This content appears to be malicious. Do not proceed.';
        icon = Icons.gpp_bad_rounded;
        gradColors = [const Color(0xFF3D0000), const Color(0xFF1A0000)];
        break;
      case 'suspicious':
        color = Colors.orangeAccent;
        title = 'Suspicious';
        subtitle = 'Potentially harmful. Proceed with caution.';
        icon = Icons.warning_amber_rounded;
        gradColors = [const Color(0xFF332200), const Color(0xFF1A1200)];
        break;
      default:
        color = Colors.greenAccent;
        title = 'All Clear';
        subtitle = 'No threats detected. This looks safe.';
        icon = Icons.verified_rounded;
        gradColors = [const Color(0xFF00331A), const Color(0xFF001A0D)];
    }

    return AnimatedOpacity(
      opacity: 1.0,
      duration: const Duration(milliseconds: 400),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: gradColors,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withOpacity(0.5), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.15),
              blurRadius: 20,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 26),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      color: color,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: color.withOpacity(0.7),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
