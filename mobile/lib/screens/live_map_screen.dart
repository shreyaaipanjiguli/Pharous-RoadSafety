import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import 'main_navigation.dart';
import '../services/route_api_service.dart';
import '../services/risk_api_service.dart';
import '../services/trip_api_service.dart';
import '../models/community_report.dart';
import '../services/report_api_service.dart';

class LiveMapScreen extends StatefulWidget {
  const LiveMapScreen({super.key});

  @override
  State<LiveMapScreen> createState() => _LiveMapScreenState();
}

class _LiveMapScreenState extends State<LiveMapScreen> {
  final MapController _mapController = MapController();
  bool _routeCameraFitted = false;

  Position? _currentPosition;
  StreamSubscription<Position>? _positionSubscription;

  bool _tracking = false;
  bool _loading = true;
  bool _fetchingRisk = false;
  String? _locationError;
  DateTime? _lastRiskFetch;
  int? _activeTripId;
  bool _tripBusy = false;
  bool _tripRestoring = false;
  bool _tripStateLoaded = false;
  DateTime? _lastTripLocationUpdate;

  List<CommunityReport> _communityReports = [];
  bool _loadingCommunityReports = false;
  String? _communityReportsError;

  static const LatLng _defaultCenter = LatLng(12.9716, 77.5946);

  @override
  void initState() {
    super.initState();
    _restoreActiveTrip();
    _startTracking();
    _loadCommunityReports();
  }

  Future<void> _restoreActiveTrip() async {
    if (_tripRestoring || _tripStateLoaded) return;

    setState(() => _tripRestoring = true);

    try {
      final activeTrip = await TripApiService.getActiveTrip();

      if (!mounted) return;

      setState(() {
        _activeTripId = activeTrip?['id'] as int?;
        _lastTripLocationUpdate = null;
        _tripStateLoaded = true;
      });

      if (_activeTripId != null && _currentPosition != null) {
        await _sendTripLocation(_currentPosition!);
      }

      if (mounted && _activeTripId != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Active trip #$_activeTripId restored.'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not verify trip status: $e'),
            action: SnackBarAction(
              label: 'RETRY',
              onPressed: _restoreActiveTrip,
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _tripRestoring = false);
      }
    }
  }

  Future<void> _startTracking() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();

      if (!serviceEnabled) {
        throw Exception('Please enable your device location service.');
      }

      LocationPermission permission = await Geolocator.checkPermission();

      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw Exception('Location permission was not granted.');
      }

      const settings = LocationSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 10,
      );

      final initialPosition = await Geolocator.getCurrentPosition(
        locationSettings: settings,
      );

      if (!mounted) return;

      _updatePosition(initialPosition);
      await _refreshRisk();

      _positionSubscription = Geolocator.getPositionStream(
        locationSettings: settings,
      ).listen(
        (position) {
          _updatePosition(position);
          _sendTripLocation(position);

          final lastFetch = _lastRiskFetch;
          if (lastFetch == null ||
              DateTime.now().difference(lastFetch).inSeconds >= 20) {
            _refreshRisk();
          }
        },
        onError: (error) {
          if (mounted) {
            setState(() {
              _locationError = 'Location updates failed: $error';
            });
          }
        },
      );

      if (mounted) {
        setState(() {
          _tracking = true;
          _loading = false;
          _locationError = null;
        });
      }
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _loading = false;
        _locationError = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  void _updatePosition(Position position) {
    if (!mounted) return;

    setState(() {
      _currentPosition = position;
      _locationError = null;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      try {
        if (!_routeCameraFitted) {
          _mapController.move(
            LatLng(position.latitude, position.longitude),
            15,
          );
        }
      } catch (_) {
        // The map may not be attached yet.
      }
    });
  }

  Future<void> _refreshRisk() async {
    if (_fetchingRisk) return;

    _fetchingRisk = true;
    _lastRiskFetch = DateTime.now();

    try {
      final result = await RiskApiService.getCurrentLocationRisk();
      debugPrint('LIVE RISK UPDATED: $result');
    } catch (e) {
      debugPrint('LIVE RISK ERROR: $e');
    } finally {
      _fetchingRisk = false;
    }
  }

  Future<void> _loadCommunityReports() async {
    if (_loadingCommunityReports) return;

    setState(() {
      _loadingCommunityReports = true;
      _communityReportsError = null;
    });

    try {
      final reports = await ReportApiService.getReports();

      if (!mounted) return;

      setState(() {
        _communityReports = reports;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _communityReportsError = e.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) {
        setState(() => _loadingCommunityReports = false);
      }
    }
  }

  Color _hazardColor(String type) {
    switch (type) {
      case 'landslide':
        return Colors.orangeAccent;
      case 'falling_rock':
        return Colors.redAccent;
      case 'blockage':
        return Colors.deepPurpleAccent;
      default:
        return Colors.amber;
    }
  }

  IconData _hazardIcon(String type) {
    switch (type) {
      case 'landslide':
        return Icons.terrain;
      case 'falling_rock':
        return Icons.landscape;
      case 'blockage':
        return Icons.block;
      default:
        return Icons.warning_amber_rounded;
    }
  }

  void _showHazardDetails(CommunityReport report) {
    final color = _hazardColor(report.type);

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF162032),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(_hazardIcon(report.type), color: color, size: 30),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        report.type.replaceAll('_', ' ').toUpperCase(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(sheetContext),
                      icon: const Icon(Icons.close, color: Colors.white70),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'Severity: ${report.severity}/3',
                  style: TextStyle(color: color, fontWeight: FontWeight.bold),
                ),
                if (report.description != null &&
                    report.description!.trim().isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    report.description!,
                    style: const TextStyle(color: Colors.white70),
                  ),
                ],
                const SizedBox(height: 12),
                Text(
                  'Confirmed: ${report.confirmVotes}   ?   Cleared: ${report.clearVotes}',
                  style: const TextStyle(color: Colors.white),
                ),
                const SizedBox(height: 8),
                Text(
                  'Coordinates: ${report.latitude.toStringAsFixed(5)}, '
                  '${report.longitude.toStringAsFixed(5)}',
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _startTrip() async {
    if (_tripBusy || _activeTripId != null) return;

    final routeData = RouteApiService.latestRouteJson;
    if (routeData == null ||
        routeData['routes'] is! List ||
        (routeData['routes'] as List).isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Calculate a route before starting a trip.'),
        ),
      );
      return;
    }

    setState(() => _tripBusy = true);

    try {
      final routes = routeData['routes'] as List;
      final selectedRoute = Map<String, dynamic>.from(routes.first as Map);

      final result = await TripApiService.startTrip(
        routeJson: {
          'routes': [selectedRoute]
        },
      );

      if (!mounted) return;

      setState(() {
        _activeTripId = result['id'] as int;
        _lastTripLocationUpdate = null;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Trip #${result['id']} started.')),
      );

      if (_currentPosition != null) {
        await _sendTripLocation(_currentPosition!);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not start trip: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _tripBusy = false);
    }
  }

  Future<void> _sendTripLocation(Position position) async {
    final tripId = _activeTripId;
    if (tripId == null) return;

    final lastUpdate = _lastTripLocationUpdate;
    if (lastUpdate != null &&
        DateTime.now().difference(lastUpdate).inSeconds < 15) {
      return;
    }

    _lastTripLocationUpdate = DateTime.now();

    try {
      await TripApiService.updateLocation(
        tripId: tripId,
        latitude: position.latitude,
        longitude: position.longitude,
      );
      debugPrint('TRIP $tripId LOCATION UPDATED');
    } catch (e) {
      debugPrint('TRIP LOCATION UPDATE ERROR: $e');
    }
  }

  Future<void> _endTrip() async {
    final tripId = _activeTripId;
    if (tripId == null || _tripBusy) return;

    setState(() => _tripBusy = true);

    try {
      await TripApiService.endTrip(tripId: tripId);

      if (!mounted) return;

      setState(() {
        _activeTripId = null;
        _lastTripLocationUpdate = null;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Trip ended successfully.')),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not end trip: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _tripBusy = false);
    }
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const PharosAppBar(),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              center: _defaultCenter,
              zoom: 13,
              minZoom: 3,
              maxZoom: 19,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.road_safe',
              ),
              ValueListenableBuilder(
                valueListenable: RouteApiService.latestRoute,
                builder: (context, response, child) {
                  if (response == null || response.routes.isEmpty) {
                    return const SizedBox.shrink();
                  }

                  final coordinates =
                      response.routes.first.geometry.coordinates;

                  if (coordinates.isEmpty) {
                    return const SizedBox.shrink();
                  }

                  final points = coordinates
                      .where((point) => point.length >= 2)
                      .map((point) => LatLng(point[1], point[0]))
                      .toList();

                  if (points.isEmpty) {
                    return const SizedBox.shrink();
                  }

                  if (!_routeCameraFitted) {
                    _routeCameraFitted = true;
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) {
                        _mapController.fitCamera(
                          CameraFit.coordinates(
                            coordinates: points,
                            padding: const EdgeInsets.all(60),
                          ),
                        );
                      }
                    });
                  }

                  return PolylineLayer(
                    polylines: [
                      Polyline(
                        points: points,
                        strokeWidth: 5,
                        color: Colors.cyanAccent,
                      ),
                    ],
                  );
                },
              ),
              MarkerLayer(
                markers: [
                  ..._communityReports.map(
                    (report) => Marker(
                      point: LatLng(report.latitude, report.longitude),
                      width: 48,
                      height: 48,
                      alignment: Alignment.bottomCenter,
                      child: GestureDetector(
                        onTap: () => _showHazardDetails(report),
                        child: Container(
                          decoration: BoxDecoration(
                            color: _hazardColor(report.type),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.white,
                              width: 2,
                            ),
                            boxShadow: const [
                              BoxShadow(
                                color: Colors.black38,
                                blurRadius: 5,
                              ),
                            ],
                          ),
                          child: Icon(
                            _hazardIcon(report.type),
                            color: Colors.white,
                            size: 25,
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (_currentPosition != null)
                    Marker(
                      point: LatLng(
                        _currentPosition!.latitude,
                        _currentPosition!.longitude,
                      ),
                      width: 55,
                      height: 55,
                      child: const Icon(
                        Icons.my_location,
                        color: Colors.blue,
                        size: 38,
                      ),
                    ),
                ],
              ),
            ],
          ),
          Positioned(
            top: 12,
            left: 12,
            right: 12,
            child: ValueListenableBuilder<Map<String, dynamic>?>(
              valueListenable: RiskApiService.latestRisk,
              builder: (context, risk, child) {
                final gaps = risk?['risk_data_gaps'] as List? ?? [];
                final assessmentComplete =
                    risk?['risk_assessment'] == 'complete';
                final liveScore = risk?['risk_score'];
                final rawFlags = risk?['risk_flags'];
                final flags = rawFlags is Map
                    ? rawFlags
                    : const <String, dynamic>{};

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
                final possibleMax = liveScore is num && flags.isNotEmpty
                    ? (liveScore.toInt() + unknownWeight).clamp(0, 100)
                    : null;

                return Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF162032).withOpacity(0.95),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.orangeAccent),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'LIVE LOCATION RISK',
                        style: TextStyle(
                          color: Colors.orangeAccent,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        assessmentComplete
                            ? 'Risk level: ${risk?['risk_level'] ?? 'Not available'}'
                            : 'Risk level: Unavailable (incomplete assessment)',
                        style: const TextStyle(color: Colors.white),
                      ),
                      Text(
                        '${assessmentComplete ? 'Risk score' : 'Partial risk score'}: ${liveScore ?? 'Not available'}',
                        style: const TextStyle(color: Colors.white),
                      ),
                      Text(
                        'Assessment: ${risk?['risk_assessment'] ?? 'Loading'}',
                        style: const TextStyle(color: Colors.white70),
                      ),
                      if (!assessmentComplete && flags.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        const Text(
                          'PROVISIONAL ASSESSMENT',
                          style: TextStyle(
                            color: Colors.orangeAccent,
                            fontWeight: FontWeight.bold,
                            fontSize: 10,
                          ),
                        ),
                        if (liveScore is num && possibleMax != null)
                          Text(
                            'Possible score: ${liveScore.toInt()}?$possibleMax',
                            style: const TextStyle(color: Colors.white),
                          ),
                        Text(
                          'Data coverage: $knownFactors/6 factors',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 11,
                          ),
                        ),
                      ],
                      if (gaps.isNotEmpty)
                        Text(
                          'Data gaps: ${gaps.join(', ')}',
                          style: const TextStyle(
                            color: Colors.orangeAccent,
                            fontSize: 11,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
          Positioned(
            bottom: 30,
            left: 12,
            right: 12,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_locationError != null)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      color: Colors.red.shade900,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      _locationError!,
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                if (_currentPosition != null)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF162032).withOpacity(0.95),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'GPS: ${_currentPosition!.latitude.toStringAsFixed(5)}, '
                      '${_currentPosition!.longitude.toStringAsFixed(5)}'
                      '\n${_tracking ? 'Live location tracking active' : 'Location available'}',
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                const SizedBox(height: 8),
                ValueListenableBuilder(
                  valueListenable: RouteApiService.latestRoute,
                  builder: (context, response, child) {
                    if (response == null || response.routes.isEmpty) {
                      return const SizedBox.shrink();
                    }

                    final route = response.routes.first;

                    return Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF162032).withOpacity(0.95),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.cyanAccent),
                      ),
                      child: Text(
                        'CALCULATED ROUTE\n'
                        'Distance: ${(route.distanceM / 1000).toStringAsFixed(2)} km\n'
                        'Risk: ${route.overallRiskLevel ?? 'Not available'}\n'
                        'Assessment: ${route.riskAssessment}',
                        style: const TextStyle(color: Colors.white),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed:
                        (_tripBusy || _tripRestoring || !_tripStateLoaded)
                            ? null
                            : (_activeTripId == null ? _startTrip : _endTrip),
                    icon: (_tripBusy || _tripRestoring || !_tripStateLoaded)
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(_activeTripId == null
                            ? Icons.play_arrow
                            : Icons.stop),
                    label: Text(
                      _tripRestoring || !_tripStateLoaded
                          ? 'PLEASE WAIT...'
                          : (_activeTripId == null ? 'START TRIP' : 'END TRIP'),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          _activeTripId == null ? Colors.green : Colors.red,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_loading)
            const Center(
              child: CircularProgressIndicator(),
            ),
          Positioned(
            right: 14,
            top: 155,
            child: FloatingActionButton.small(
              heroTag: 'refresh_community_hazards',
              onPressed:
                  _loadingCommunityReports ? null : _loadCommunityReports,
              tooltip: 'Refresh community hazards',
              child: _loadingCommunityReports
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh),
            ),
          ),
          if (_communityReportsError != null)
            Positioned(
              top: 155,
              left: 12,
              right: 70,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.shade900,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Hazards unavailable: $_communityReportsError',
                  style: const TextStyle(color: Colors.white, fontSize: 11),
                ),
              ),
            ),
          Positioned(
            right: 14,
            bottom: 14,
            child: FloatingActionButton.small(
              heroTag: 'refresh_live_location',
              onPressed: _startTracking,
              child: const Icon(Icons.my_location),
            ),
          ),
          const Positioned(
            left: 8,
            top: 155,
            child: Text(
              'Ã‚Â© OpenStreetMap contributors',
              style: TextStyle(
                fontSize: 10,
                color: Colors.black87,
                backgroundColor: Colors.white70,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
