import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../services/route_api_service.dart';
import '../models/route_response.dart';
import 'main_navigation.dart';

class RoutePlannerScreen extends StatefulWidget {
  const RoutePlannerScreen({super.key});

  @override
  State<RoutePlannerScreen> createState() => _RoutePlannerScreenState();
}

class _RoutePlannerScreenState extends State<RoutePlannerScreen> {
  final _originController = TextEditingController();
  final _destController = TextEditingController();

  bool _calculating = false;
  bool _locatingOrigin = false;
  String? _error;
  RouteCollectionResponse? _result;

  @override
  void dispose() {
    _originController.dispose();
    _destController.dispose();
    super.dispose();
  }

  /// Parse "lat,lon" from a text field.
  ({double lat, double lon})? _parseCoords(String text) {
    final parts = text.trim().split(',');
    if (parts.length != 2) return null;
    final lat = double.tryParse(parts[0].trim());
    final lon = double.tryParse(parts[1].trim());
    if (lat == null || lon == null) return null;
    return (lat: lat, lon: lon);
  }

  Future<void> _useCurrentLocation() async {
    setState(() {
      _locatingOrigin = true;
      _error = null;
    });
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) throw Exception('Location service disabled.');

      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        throw Exception('Location permission denied.');
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings:
            const LocationSettings(accuracy: LocationAccuracy.high),
      );
      if (!mounted) return;
      _originController.text =
          '${position.latitude.toStringAsFixed(6)},${position.longitude.toStringAsFixed(6)}';
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _locatingOrigin = false);
    }
  }

  Future<void> _calculate() async {
    setState(() {
      _error = null;
      _result = null;
    });

    final origin = _parseCoords(_originController.text);
    final dest = _parseCoords(_destController.text);

    if (origin == null) {
      setState(() => _error = 'Enter origin as "latitude,longitude".');
      return;
    }
    if (dest == null) {
      setState(() => _error = 'Enter destination as "latitude,longitude".');
      return;
    }

    setState(() => _calculating = true);

    try {
      final result = await RouteApiService.calculateRoute(
        originLatitude: origin.lat,
        originLongitude: origin.lon,
        destinationLatitude: dest.lat,
        destinationLongitude: dest.lon,
      );
      if (!mounted) return;
      setState(() {
        _result = result;
        _calculating = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _calculating = false;
      });
    }
  }

  Color _riskColor(String? level) {
    switch (level?.toLowerCase()) {
      case 'low':
        return Colors.green;
      case 'medium':
        return Colors.orange;
      case 'high':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  Widget _buildRouteCard(RouteOption route, int index) {
    final riskLevel = route.overallRiskLevel;
    final color = _riskColor(riskLevel);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF162032),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.alt_route, color: color, size: 20),
              const SizedBox(width: 8),
              Text(
                'Route ${index + 1}',
                style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.bold,
                    fontSize: 15),
              ),
              const Spacer(),
              if (riskLevel != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: color.withOpacity(0.5)),
                  ),
                  child: Text(
                    riskLevel.toUpperCase(),
                    style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.bold,
                        fontSize: 11),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          _infoRow(
              Icons.straighten,
              'Distance',
              '${(route.distanceM / 1000).toStringAsFixed(2)} km'),
          const SizedBox(height: 4),
          _infoRow(Icons.assessment, 'Assessment', route.riskAssessment),
          if (route.overallRiskScore != null) ...[
            const SizedBox(height: 4),
            _infoRow(
              Icons.speed,
              route.riskAssessment == 'complete'
                  ? 'Risk score'
                  : 'Partial risk score',
              route.overallRiskScore!.toStringAsFixed(2),
            ),
          ],
          if (route.overallRiskCoveragePercent != null) ...[
            const SizedBox(height: 4),
            _infoRow(
              Icons.data_usage,
              'Score coverage',
              '${route.overallRiskCoveragePercent!.toStringAsFixed(1)}%',
            ),
          ],
          if (route.overallRiskCoveredDistanceM != null) ...[
            const SizedBox(height: 4),
            _infoRow(
              Icons.straighten,
              'Scored distance',
              '${(route.overallRiskCoveredDistanceM! / 1000).toStringAsFixed(2)} km',
            ),
          ],
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, color: Colors.grey, size: 15),
        const SizedBox(width: 6),
        Text('$label: ', style: const TextStyle(color: Colors.grey, fontSize: 12)),
        Expanded(
          child: Text(value,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
              overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Colors.grey, fontSize: 12),
      filled: true,
      fillColor: const Color(0xFF162032),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide.none,
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
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Route Planner',
              style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.white),
            ),
            const SizedBox(height: 4),
            const Text(
              'Enter coordinates as "latitude,longitude".',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
            const SizedBox(height: 20),

            // Origin
            Row(
              children: [
                const Icon(Icons.trip_origin, color: Colors.green, size: 18),
                const SizedBox(width: 8),
                const Text('Origin',
                    style: TextStyle(color: Colors.white70, fontSize: 13)),
                const Spacer(),
                TextButton.icon(
                  onPressed: _locatingOrigin ? null : _useCurrentLocation,
                  icon: _locatingOrigin
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.my_location, size: 14),
                  label: const Text('Use GPS', style: TextStyle(fontSize: 12)),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.cyanAccent,
                    padding: EdgeInsets.zero,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _originController,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              keyboardType: const TextInputType.numberWithOptions(
                  signed: true, decimal: true),
              decoration: _inputDecoration('e.g. 12.879189, 75.721304'),
            ),

            const SizedBox(height: 14),

            // Destination
            const Row(
              children: [
                Icon(Icons.location_on, color: Colors.redAccent, size: 18),
                SizedBox(width: 8),
                Text('Destination',
                    style: TextStyle(color: Colors.white70, fontSize: 13)),
              ],
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _destController,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              keyboardType: const TextInputType.numberWithOptions(
                  signed: true, decimal: true),
              decoration: _inputDecoration('e.g. 12.831463, 75.542298'),
            ),

            const SizedBox(height: 20),

            if (_error != null)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.red.shade900.withOpacity(0.35),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _error!,
                  style:
                      const TextStyle(color: Colors.redAccent, fontSize: 13),
                ),
              ),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _calculating ? null : _calculate,
                icon: _calculating
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.directions),
                label:
                    Text(_calculating ? 'Calculating…' : 'Calculate Route'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0055FF),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  textStyle: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 15),
                ),
              ),
            ),

            if (_result != null) ...[
              const SizedBox(height: 24),
              const Text(
                'Results',
                style: TextStyle(
                    color: Colors.white70,
                    fontWeight: FontWeight.w600,
                    fontSize: 14),
              ),
              const SizedBox(height: 10),
              ..._result!.routes
                  .asMap()
                  .entries
                  .map((e) => _buildRouteCard(e.value, e.key)),
              const SizedBox(height: 8),
              const Center(
                child: Text(
                  'Open the Map tab to see the route overlay.',
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
