import 'package:flutter/material.dart';
import 'dart:math' as math;

import '../services/notification_service.dart';
import '../services/risk_api_service.dart';
import 'main_navigation.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _loading = false;
  String? _error;
  bool _notificationsEnabled = false;
  bool _enablingNotifications = false;

  Future<void> _refreshRisk() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await RiskApiService.getCurrentLocationRisk();
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceFirst('Exception: ', '');
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _enableNotifications() async {
    if (_enablingNotifications || _notificationsEnabled) return;

    setState(() {
      _enablingNotifications = true;
    });

    try {
      final message = await NotificationService.enableNotifications();

      if (!mounted) return;

      setState(() {
        _notificationsEnabled = true;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _enablingNotifications = false;
        });
      }
    }
  }

  Color _riskColor(String? level) {
    switch (level?.toLowerCase()) {
      case 'low':
      case 'green':
        return Colors.greenAccent;
      case 'moderate':
      case 'yellow':
        return Colors.yellowAccent;
      case 'high':
      case 'orange':
        return Colors.orangeAccent;
      case 'severe':
      case 'critical':
      case 'red':
        return Colors.redAccent;
      default:
        return Colors.cyanAccent;
    }
  }

  List<String> _strings(dynamic value) =>
      value is List ? value.whereType<String>().toList() : [];

  Widget _items(String title, List<String> values) {
    if (values.isEmpty) return const SizedBox.shrink();
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                )),
            const SizedBox(height: 6),
            ...values.map((value) => Padding(
                  padding: const EdgeInsets.only(bottom: 5),
                  child: Text('• $value',
                      style: const TextStyle(color: Colors.grey, fontSize: 12)),
                )),
          ],
        ),
      ),
    );
  }

  Widget _riskPanel(Map<String, dynamic>? risk) {
    final complete = risk?['risk_assessment'] == 'complete';
    final rawScore = risk?['risk_score'];
    final rawLevel = risk?['risk_level'];
    final score = rawScore is num ? rawScore.toInt() : null;
    // Always display a real numeric score, even if its risk level is unavailable.
    // Never display a risk category for an incomplete assessment.
    final level = complete ? rawLevel?.toString() : null;
    final showScore = score != null;
    final showLevel = complete && level != null;
    final color = _riskColor(level);
    final gaps = _strings(risk?['risk_data_gaps']);
    final reasons = _strings(risk?['reasons']);
    final distance = risk?['road_match_distance_m'];
    final rawFlags = risk?['risk_flags'];
    final flags = rawFlags is Map ? rawFlags : const <String, dynamic>{};

    const factorWeights = <String, int>{
      'heavy_rain': 30,
      'landslide_history': 25,
      'steep_slope': 20,
      'recent_hazard_report': 40,
      'heavy_traffic': 25,
      'low_visibility': 15,
    };
    final knownFactors = factorWeights.keys
        .where((key) => flags[key] != null)
        .length;
    final unknownWeight = factorWeights.entries
        .where((entry) => flags[entry.key] == null)
        .fold<int>(0, (sum, entry) => sum + entry.value);
    final possibleMax = score != null && flags.isNotEmpty
        ? (score + unknownWeight).clamp(0, 100)
        : null;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF162032),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('LIVE ROAD RISK',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.6,
                  )),
              IconButton(
                tooltip: 'Refresh assessment',
                onPressed: _loading ? null : _refreshRisk,
                icon: _loading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.cyanAccent,
                        ),
                      )
                    : const Icon(Icons.refresh, color: Colors.cyanAccent),
              ),
            ],
          ),
          if (showScore) ...[
            SizedBox(
              height: 112,
              width: 190,
              child: CustomPaint(
                painter: GaugePainter(score: score.clamp(0, 100)),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                        complete ? 'RISK SCORE' : 'PARTIAL RISK SCORE',
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 10,
                          letterSpacing: 1.2,
                        )),
                    Text('$score',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                        )),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
                showLevel
                    ? '${level!.toUpperCase()} RISK'
                    : complete
                        ? 'RISK LEVEL UNAVAILABLE'
                        : 'PARTIAL SCORE - NO RISK LEVEL',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: showLevel ? color : Colors.orangeAccent,
                  fontWeight: FontWeight.bold,
                )),
          ] else ...[
            const Icon(Icons.shield_outlined,
                color: Colors.cyanAccent, size: 42),
            const SizedBox(height: 10),
            Text(
              risk == null
                  ? 'Risk assessment not started'
                  : 'Risk score unavailable',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              risk == null
                  ? 'Assess your current location for live road-risk information.'
                  : 'Available data is not sufficient for a complete assessment.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ],
          const SizedBox(height: 10),
          Text(
            risk == null
                ? 'No assessment yet'
                : complete
                    ? 'Assessment complete'
                    : 'Assessment incomplete',
            style: TextStyle(
              color: complete ? Colors.greenAccent : Colors.orangeAccent,
              fontSize: 12,
            ),
          ),
          if (!complete && flags.isNotEmpty) ...[
            const SizedBox(height: 6),
            const Text(
              'PROVISIONAL ASSESSMENT',
              style: TextStyle(
                color: Colors.orangeAccent,
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.8,
              ),
            ),
            if (score != null && possibleMax != null)
              Text(
                'Possible score: $score?$possibleMax',
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
            Text(
              'Data coverage: $knownFactors/6 factors',
              style: const TextStyle(color: Colors.white70, fontSize: 11),
            ),
          ],
          if (distance is num)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Nearest matched road: ${distance.toStringAsFixed(1)} m away',
                style: const TextStyle(color: Colors.grey, fontSize: 11),
              ),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(_error!,
                  textAlign: TextAlign.center,
                  style:
                      const TextStyle(color: Colors.redAccent, fontSize: 12)),
            ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _loading ? null : _refreshRisk,
              icon: const Icon(Icons.my_location),
              label: Text(_loading
                  ? 'Assessing location...'
                  : 'Assess Current Location'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.cyanAccent,
                foregroundColor: const Color(0xFF0F172A),
                padding: const EdgeInsets.symmetric(vertical: 13),
              ),
            ),
          ),
          _items('Assessment reasons', reasons),
          _items('Data unavailable', gaps),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const PharosAppBar(),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            ValueListenableBuilder<Map<String, dynamic>?>(
              valueListenable: RiskApiService.latestRisk,
              builder: (context, risk, child) => _riskPanel(risk),
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF162032),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: Colors.cyanAccent.withOpacity(0.35),
                ),
              ),
              child: Column(
                children: [
                  const Icon(Icons.notifications_active_outlined,
                      color: Colors.cyanAccent, size: 32),
                  const SizedBox(height: 8),
                  const Text('Stay Updated with Pharos',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  const Text(
                    'Enable notifications to receive safety alerts.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: (_enablingNotifications || _notificationsEnabled)
                          ? null
                          : _enableNotifications,
                      icon: Icon(
                        _notificationsEnabled
                            ? Icons.notifications_active
                            : Icons.notifications,
                      ),
                      label: Text(
                        _notificationsEnabled
                            ? 'Notifications Enabled'
                            : _enablingNotifications
                                ? 'Enabling Notifications...'
                                : 'Enable Notifications',
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _notificationsEnabled
                            ? Colors.greenAccent
                            : Colors.cyanAccent,
                        foregroundColor: const Color(0xFF0F172A),
                        disabledBackgroundColor: _notificationsEnabled
                            ? Colors.greenAccent
                            : Colors.cyanAccent.withOpacity(0.6),
                        disabledForegroundColor: const Color(0xFF0F172A),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                      ),
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

class GaugePainter extends CustomPainter {
  final int score;
  GaugePainter({required this.score});

  @override
  void paint(Canvas canvas, Size size) {
    final background = Paint()
      ..color = Colors.white12
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12
      ..strokeCap = StrokeCap.round;

    final arc = Paint()
      ..shader = const SweepGradient(
        colors: [Colors.green, Colors.yellow, Colors.orange, Colors.red],
        stops: [0.0, 0.35, 0.7, 1.0],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12
      ..strokeCap = StrokeCap.round;

    final center = Offset(size.width / 2, size.height);
    final radius = size.width / 2 - 10;
    final rect = Rect.fromCircle(center: center, radius: radius);

    canvas.drawArc(rect, math.pi, math.pi, false, background);
    canvas.drawArc(
      rect,
      math.pi,
      math.pi * (score.clamp(0, 100) / 100),
      false,
      arc,
    );
  }

  @override
  bool shouldRepaint(covariant GaugePainter oldDelegate) =>
      oldDelegate.score != score;
}
