import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../services/auth_service.dart';
import 'main_navigation.dart';

class ReportHazardScreen extends StatefulWidget {
  const ReportHazardScreen({super.key});

  @override
  State<ReportHazardScreen> createState() => _ReportHazardScreenState();
}

class _ReportHazardScreenState extends State<ReportHazardScreen> {
  static const List<Map<String, String>> _hazardTypes = [
    {'value': 'landslide', 'label': 'Landslide'},
    {'value': 'falling_rock', 'label': 'Falling Rock'},
    {'value': 'blockage', 'label': 'Road Blockage'},
  ];

  final _descController = TextEditingController();
  final _latitudeController = TextEditingController();
  final _longitudeController = TextEditingController();

  bool _useManualLocation = false;

  String _selectedType = 'landslide';
  int _severity = 2;
  bool _locating = false;
  bool _submitting = false;
  Position? _currentPosition;
  String? _locationError;
  String? _submitError;

  @override
  void initState() {
    super.initState();
    _fetchLocation();
  }

  @override
  void dispose() {
    _descController.dispose();
    _latitudeController.dispose();
    _longitudeController.dispose();
    super.dispose();
  }

  Future<void> _fetchLocation() async {
    setState(() {
      _locating = true;
      _locationError = null;
    });

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        throw Exception('Location service is disabled.');
      }

      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        throw Exception('Location permission denied.');
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );

      if (!mounted) return;
      setState(() {
        _currentPosition = position;
        _locating = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _locationError = e.toString().replaceFirst('Exception: ', '');
        _locating = false;
      });
    }
  }

  Future<void> _submit() async {
    if (!AuthService.isLoggedIn) {
      setState(() => _submitError = 'Please log in to submit a hazard report.');
      return;
    }

    double latitude;
    double longitude;

    if (_useManualLocation) {
      latitude = double.tryParse(_latitudeController.text.trim()) ?? double.nan;
      longitude =
          double.tryParse(_longitudeController.text.trim()) ?? double.nan;

      if (!latitude.isFinite ||
          !longitude.isFinite ||
          latitude < -90 ||
          latitude > 90 ||
          longitude < -180 ||
          longitude > 180) {
        setState(() {
          _submitError =
              'Enter valid coordinates. Latitude: -90 to 90, longitude: -180 to 180.';
        });
        return;
      }
    } else {
      final pos = _currentPosition;
      if (pos == null) {
        setState(() {
          _submitError =
              'GPS location is unavailable. Use manual location instead.';
        });
        return;
      }

      latitude = pos.latitude;
      longitude = pos.longitude;
    }

    final description = _descController.text.trim();

    setState(() {
      _submitting = true;
      _submitError = null;
    });

    try {
      final url = Uri.parse('${ApiConfig.baseUrl}/reports');
      final response = await http
          .post(
            url,
            headers: AuthService.authenticatedHeaders,
            body: jsonEncode({
              'type': _selectedType,
              'severity': _severity,
              'description': description.isEmpty ? null : description,
              'latitude': latitude,
              'longitude': longitude,
            }),
          )
          .timeout(const Duration(seconds: 20));

      if (!mounted) return;

      if (response.statusCode == 201) {
        _descController.clear();
        setState(() {
          _selectedType = 'landslide';
          _severity = 2;
          _submitting = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Hazard reported successfully.'),
            backgroundColor: Colors.green,
          ),
        );
      } else if (response.statusCode == 401) {
        await AuthService.handleUnauthorized();
        setState(() {
          _submitError = 'Session expired. Please log in again.';
          _submitting = false;
        });
      } else if (response.statusCode == 429) {
        setState(() {
          _submitError = 'Report limit reached. Try again later.';
          _submitting = false;
        });
      } else {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        setState(() {
          _submitError = (body['detail'] as String?) ??
              'Failed to submit report (HTTP ${response.statusCode}).';
          _submitting = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitError = e.toString().replaceFirst('Exception: ', '');
        _submitting = false;
      });
    }
  }

  Widget _buildSeverityChip(int value, String label, Color color) {
    final selected = _severity == value;
    return GestureDetector(
      onTap: () => setState(() => _severity = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? color.withOpacity(0.25) : const Color(0xFF0F172A),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? color : Colors.white24,
            width: selected ? 2 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? color : Colors.white54,
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
            fontSize: 13,
          ),
        ),
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
              'Report Road Hazard',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Report a hazard using GPS or manually entered coordinates.',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
            const SizedBox(height: 20),

            // GPS status
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF162032),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _currentPosition != null
                      ? Colors.green.withOpacity(0.5)
                      : Colors.orange.withOpacity(0.5),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _currentPosition != null
                        ? Icons.location_on
                        : (_locating
                            ? Icons.gps_not_fixed
                            : Icons.location_off),
                    color: _currentPosition != null
                        ? Colors.greenAccent
                        : Colors.orange,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _locating
                        ? const Text(
                            'Obtaining GPS location…',
                            style:
                                TextStyle(color: Colors.orange, fontSize: 12),
                          )
                        : _currentPosition != null
                            ? Text(
                                '${_currentPosition!.latitude.toStringAsFixed(5)}, '
                                '${_currentPosition!.longitude.toStringAsFixed(5)}',
                                style: const TextStyle(
                                    color: Colors.greenAccent, fontSize: 12),
                              )
                            : Text(
                                _locationError ?? 'Location unavailable.',
                                style: const TextStyle(
                                    color: Colors.orange, fontSize: 12),
                              ),
                  ),
                  if (!_locating)
                    IconButton(
                      icon: const Icon(Icons.refresh,
                          color: Colors.grey, size: 18),
                      onPressed: _fetchLocation,
                      tooltip: 'Refresh location',
                    ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // Location selection
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      setState(() {
                        _useManualLocation = false;
                        _submitError = null;
                      });
                    },
                    icon: const Icon(Icons.gps_fixed, size: 18),
                    label: const Text('Use GPS'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: !_useManualLocation
                          ? Colors.teal
                          : const Color(0xFF162032),
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      setState(() {
                        _useManualLocation = true;
                        _submitError = null;
                        if (_currentPosition != null &&
                            _latitudeController.text.isEmpty &&
                            _longitudeController.text.isEmpty) {
                          _latitudeController.text =
                              _currentPosition!.latitude.toString();
                          _longitudeController.text =
                              _currentPosition!.longitude.toString();
                        }
                      });
                    },
                    icon: const Icon(Icons.edit_location_alt, size: 18),
                    label: const Text('Enter manually'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _useManualLocation
                          ? Colors.teal
                          : const Color(0xFF162032),
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ],
            ),

            if (_useManualLocation) ...[
              const SizedBox(height: 14),
              const Text(
                'Enter hazard coordinates',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _latitudeController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                        signed: true,
                      ),
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: 'Latitude',
                        labelStyle: const TextStyle(color: Colors.grey),
                        hintText: '12.910443',
                        hintStyle: const TextStyle(color: Colors.white38),
                        filled: true,
                        fillColor: const Color(0xFF162032),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _longitudeController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                        signed: true,
                      ),
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: 'Longitude',
                        labelStyle: const TextStyle(color: Colors.grey),
                        hintText: '77.566675',
                        hintStyle: const TextStyle(color: Colors.white38),
                        filled: true,
                        fillColor: const Color(0xFF162032),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              const Text(
                'Use decimal coordinates. Example: 12.910443, 77.566675',
                style: TextStyle(color: Colors.white54, fontSize: 11),
              ),
            ],

            const SizedBox(height: 20),

            // Hazard type
            const Text(
              'Hazard Type',
              style: TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                  fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFF162032),
                borderRadius: BorderRadius.circular(10),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: DropdownButton<String>(
                value: _selectedType,
                isExpanded: true,
                dropdownColor: const Color(0xFF162032),
                underline: const SizedBox(),
                style: const TextStyle(color: Colors.white),
                items: _hazardTypes.map((t) {
                  return DropdownMenuItem<String>(
                    value: t['value'],
                    child: Text(t['label']!),
                  );
                }).toList(),
                onChanged: (v) {
                  if (v != null) setState(() => _selectedType = v);
                },
              ),
            ),

            const SizedBox(height: 20),

            // Severity
            const Text(
              'Severity',
              style: TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                  fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildSeverityChip(1, 'Low', Colors.green),
                _buildSeverityChip(2, 'Medium', Colors.orange),
                _buildSeverityChip(3, 'High', Colors.red),
              ],
            ),

            const SizedBox(height: 20),

            // Description
            const Text(
              'Description (optional)',
              style: TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                  fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _descController,
              maxLines: 3,
              maxLength: 500,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Describe the hazard (e.g., fallen tree at km 42)…',
                hintStyle: const TextStyle(color: Colors.grey),
                filled: true,
                fillColor: const Color(0xFF162032),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
                counterStyle: const TextStyle(color: Colors.grey),
              ),
            ),

            if (_submitError != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.red.shade900.withOpacity(0.4),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _submitError!,
                  style: const TextStyle(color: Colors.redAccent, fontSize: 13),
                ),
              ),
            ],

            const SizedBox(height: 20),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: (_submitting || _locating) ? null : _submit,
                icon: _submitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.warning_amber_rounded),
                label:
                    Text(_submitting ? 'Submitting…' : 'Submit Hazard Report'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orangeAccent,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  textStyle: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 15),
                ),
              ),
            ),

            if (!AuthService.isLoggedIn) ...[
              const SizedBox(height: 10),
              const Center(
                child: Text(
                  'You must be logged in to submit a report.',
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
