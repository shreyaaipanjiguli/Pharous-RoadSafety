import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../models/community_report.dart';
import '../services/report_api_service.dart';
import '../services/auth_service.dart';
import 'main_navigation.dart';

class CommunityScreen extends StatefulWidget {
  const CommunityScreen({super.key});

  @override
  State<CommunityScreen> createState() => _CommunityScreenState();
}

class _CommunityScreenState extends State<CommunityScreen> {
  List<CommunityReport> _reports = [];
  bool _loading = true;
  bool _nearbyOnly = false;
  String _filter = 'all';
  String? _error;
  Position? _position;
  final Set<int> _votingReports = {};

  @override
  void initState() {
    super.initState();
    _loadReports();
  }

  Future<void> _loadReports() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      Position? position;

      if (_nearbyOnly) {
        final enabled = await Geolocator.isLocationServiceEnabled();
        if (!enabled) {
          throw Exception(
              'Please enable location services for Nearby reports.');
        }

        var permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied) {
          permission = await Geolocator.requestPermission();
        }

        if (permission == LocationPermission.denied ||
            permission == LocationPermission.deniedForever) {
          throw Exception(
              'Location permission is required for Nearby reports.');
        }

        position = await Geolocator.getCurrentPosition();
      }

      final reports = await ReportApiService.getReports(
        type: _filter,
        minLatitude: position == null ? null : position.latitude - 0.25,
        minLongitude: position == null ? null : position.longitude - 0.25,
        maxLatitude: position == null ? null : position.latitude + 0.25,
        maxLongitude: position == null ? null : position.longitude + 0.25,
      );

      if (!mounted) return;

      setState(() {
        _position = position;
        _reports = reports;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  double? _distanceKm(CommunityReport report) {
    if (_position == null) return null;
    return Geolocator.distanceBetween(
          _position!.latitude,
          _position!.longitude,
          report.latitude,
          report.longitude,
        ) /
        1000;
  }

  Color _severityColor(int severity) {
    if (severity == 3) return Colors.redAccent;
    if (severity == 2) return Colors.orangeAccent;
    return Colors.greenAccent;
  }

  String _title(String type) {
    switch (type) {
      case 'falling_rock':
        return 'Falling rocks';
      case 'blockage':
        return 'Road blockage';
      case 'landslide':
        return 'Landslide';
      default:
        return type.replaceAll('_', ' ');
    }
  }

  @override
  Widget build(BuildContext context) {
    final visibleReports = _nearbyOnly && _position != null
        ? _reports
            .where((report) => (_distanceKm(report) ?? 999) <= 25)
            .toList()
        : _reports;

    return Scaffold(
      appBar: const PharosAppBar(),
      body: RefreshIndicator(
        onRefresh: _loadReports,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'Community Reports',
              style: TextStyle(fontSize: 23, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            const Text(
              'Road hazards reported by the Pharos community.',
              style: TextStyle(color: Colors.white60),
            ),
            const SizedBox(height: 18),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('All Reports')),
                ButtonSegment(value: true, label: Text('Nearby 25 km')),
              ],
              selected: {_nearbyOnly},
              onSelectionChanged: (selection) {
                setState(() => _nearbyOnly = selection.first);
                _loadReports();
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _filter,
              decoration: const InputDecoration(
                labelText: 'Filter hazard type',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 'all', child: Text('All types')),
                DropdownMenuItem(value: 'landslide', child: Text('Landslides')),
                DropdownMenuItem(
                    value: 'falling_rock', child: Text('Falling rocks')),
                DropdownMenuItem(
                    value: 'blockage', child: Text('Road blockages')),
              ],
              onChanged: (value) {
                if (value == null) return;
                setState(() => _filter = value);
                _loadReports();
              },
            ),
            const SizedBox(height: 16),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              _message(
                Icons.error_outline,
                _error!,
                action: TextButton(
                  onPressed: _loadReports,
                  child: const Text('Retry'),
                ),
              )
            else if (visibleReports.isEmpty)
              _message(
                Icons.verified_user_outlined,
                _nearbyOnly
                    ? 'No active reports found within 25 km.'
                    : 'No active community reports found.',
              )
            else ...[
              Text(
                '${visibleReports.length} active report(s)',
                style: const TextStyle(
                  color: Colors.cyanAccent,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 10),
              ...visibleReports.map(_reportCard),
            ],
          ],
        ),
      ),
    );
  }

  Widget _message(IconData icon, String message, {Widget? action}) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Icon(icon, size: 42, color: Colors.white54),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
          if (action != null) action,
        ],
      ),
    );
  }

  Future<void> _castVote(CommunityReport report, String vote) async {
    if (!AuthService.isLoggedIn) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please log in to vote on reports.')),
      );
      return;
    }

    setState(() => _votingReports.add(report.id));

    try {
      await ReportApiService.vote(reportId: report.id, vote: vote);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            vote == 'confirm'
                ? 'Hazard confirmed successfully.'
                : 'Hazard marked as cleared.',
          ),
        ),
      );

      await _loadReports();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _votingReports.remove(report.id));
      }
    }
  }

  Widget _reportCard(CommunityReport report) {
    final color = _severityColor(report.severity);
    final distance = _distanceKm(report);

    return Card(
      color: const Color(0xFF1E293B),
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: color.withValues(alpha: 0.35)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    _title(report.type),
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Text(
                  'SEVERITY ${report.severity}',
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              report.description?.isNotEmpty == true
                  ? report.description!
                  : 'No additional description provided.',
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.location_on_outlined,
                    size: 16, color: Colors.cyanAccent),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    '${report.latitude.toStringAsFixed(4)}, '
                    '${report.longitude.toStringAsFixed(4)}',
                    style: const TextStyle(color: Colors.white60, fontSize: 12),
                  ),
                ),
                if (distance != null)
                  Text(
                    '${distance.toStringAsFixed(1)} km away',
                    style: const TextStyle(
                      color: Colors.cyanAccent,
                      fontSize: 12,
                    ),
                  ),
              ],
            ),
            const Divider(height: 22),
            Row(
              children: [
                const Icon(Icons.thumb_up_alt_outlined,
                    size: 16, color: Colors.greenAccent),
                const SizedBox(width: 5),
                Text('${report.confirmVotes} confirmed'),
                const SizedBox(width: 16),
                const Icon(Icons.check_circle_outline,
                    size: 16, color: Colors.orangeAccent),
                const SizedBox(width: 5),
                Text('${report.clearVotes} cleared'),
              ],
            ),
            const SizedBox(height: 8),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _votingReports.contains(report.id)
                        ? null
                        : () => _castVote(report, 'confirm'),
                    icon: const Icon(Icons.thumb_up_alt_outlined),
                    label: const Text('Confirm hazard'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _votingReports.contains(report.id)
                        ? null
                        : () => _castVote(report, 'clear'),
                    icon: const Icon(Icons.check_circle_outline),
                    label: const Text('Mark cleared'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Reported ${report.createdAt.toLocal()}',
              style: const TextStyle(color: Colors.white38, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}
