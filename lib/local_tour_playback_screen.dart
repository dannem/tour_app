// File: lib/local_tour_playback_screen.dart
// Playback screen for locally stored tours

import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:just_audio/just_audio.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'local_tour_manager.dart';
import 'main.dart';

class LocalTourPlaybackScreen extends StatefulWidget {
  final LocalTour tour;

  const LocalTourPlaybackScreen({super.key, required this.tour});

  @override
  State<LocalTourPlaybackScreen> createState() => _LocalTourPlaybackScreenState();
}

class _LocalTourPlaybackScreenState extends State<LocalTourPlaybackScreen> {
  final Completer<GoogleMapController> _mapController = Completer();
  final AudioPlayer _audioPlayer = AudioPlayer();
  final FlutterTts _tts = FlutterTts();

  StreamSubscription<Position>? _positionStreamSubscription;
  StreamSubscription? _playerStateSubscription;

  Set<Marker> _markers = {};
  int _currentPointIndex = 0;
  String _statusMessage = 'Loading tour...';
  bool _isAudioPlaying = false;

  PlaybackMode _playbackMode = PlaybackMode.sequential;
  Set<int> _completedWaypoints = {};
  bool _tourStarted = false;

  @override
  void initState() {
    super.initState();
    _initializeTts();
    _loadTourData();

    _playerStateSubscription = _audioPlayer.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _handleAudioCompleted();
          }
        });
      }
    });
  }

  Future<void> _initializeTts() async {
    await _tts.setLanguage('en-US');
    await _tts.setSpeechRate(0.5);
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);

    _tts.setCompletionHandler(() {
      setState(() {
        _isAudioPlaying = false;
        _completedWaypoints.add(_currentPointIndex);

        if (_playbackMode == PlaybackMode.sequential) {
          _moveToNextWaypoint();
        } else {
          _statusMessage = "Waypoint completed! Approach another waypoint.";
          _updateMarkers();
        }
      });
    });
  }

  void _loadTourData() {
    setState(() {
      _statusMessage = '${widget.tour.name} loaded. Choose playback mode and start tour.';
      _updateMarkers();
    });
  }

  void _updateMarkers() {
    final newMarkers = <Marker>{};

    for (int i = 0; i < widget.tour.waypoints.length; i++) {
      final point = widget.tour.waypoints[i];
      final isCompleted = _completedWaypoints.contains(i);
      final isCurrent = i == _currentPointIndex && _tourStarted;

      newMarkers.add(
        Marker(
          markerId: MarkerId('point_$i'),
          position: LatLng(point.latitude, point.longitude),
          infoWindow: InfoWindow(
            title: point.name ?? 'Waypoint ${i + 1}',
            snippet: isCompleted ? 'Completed ✓' : 'Pending',
          ),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            isCompleted
              ? BitmapDescriptor.hueViolet
              : isCurrent
                ? BitmapDescriptor.hueGreen
                : BitmapDescriptor.hueRed,
          ),
        ),
      );
    }

    setState(() {
      _markers = newMarkers;
    });
  }

  void _startTour() {
    setState(() {
      _tourStarted = true;
      _currentPointIndex = 0;
      _completedWaypoints.clear();
      _statusMessage = _playbackMode == PlaybackMode.sequential
        ? 'Tour started! Playing waypoint 1...'
        : 'Tour started! Approach any waypoint to hear it.';
      _updateMarkers();
    });

    _startLocationListener();

    if (_playbackMode == PlaybackMode.sequential) {
      _playCurrentWaypoint();
    }
  }

  void _startLocationListener() {
    const locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 5,
    );

    _positionStreamSubscription = Geolocator.getPositionStream(
      locationSettings: locationSettings,
    ).listen((Position position) {
      if (!_tourStarted) return;

      if (_playbackMode == PlaybackMode.proximity) {
        _checkProximityToWaypoints(position);
      }
    });
  }

  void _checkProximityToWaypoints(Position userPosition) {
    for (int i = 0; i < widget.tour.waypoints.length; i++) {
      if (_completedWaypoints.contains(i)) continue;
      if (_isAudioPlaying) continue;

      final point = widget.tour.waypoints[i];
      final distance = Geolocator.distanceBetween(
        userPosition.latitude,
        userPosition.longitude,
        point.latitude,
        point.longitude,
      );

      if (distance < 20) {
        setState(() {
          _currentPointIndex = i;
        });
        _playCurrentWaypoint();
        break;
      }
    }
  }

  Future<void> _playCurrentWaypoint() async {
    if (_currentPointIndex >= widget.tour.waypoints.length) return;

    final point = widget.tour.waypoints[_currentPointIndex];

    setState(() {
      _isAudioPlaying = true;
      _statusMessage = 'Playing: ${point.name ?? "Waypoint ${_currentPointIndex + 1}"}';
      _updateMarkers();
    });

    try {
      // Check if this waypoint has text (Wikipedia) or audio file
      if (point.text != null && point.text!.isNotEmpty) {
        // Use TTS for Wikipedia articles
        await _tts.speak(point.text!);
      } else if (point.localAudioPath != null) {
        // Play audio file
        final audioFile = File(point.localAudioPath!);
        if (await audioFile.exists()) {
          await _audioPlayer.setFilePath(point.localAudioPath!);
          await _audioPlayer.play();
        } else {
          throw Exception('Audio file not found');
        }
      } else {
        throw Exception('No audio or text available for this waypoint');
      }
    } catch (e) {
      print('Error playing waypoint: $e');
      setState(() {
        _isAudioPlaying = false;
        _statusMessage = 'Error playing waypoint: $e';
      });
    }
  }

  void _handleAudioCompleted() {
    setState(() {
      _isAudioPlaying = false;
      _completedWaypoints.add(_currentPointIndex);

      if (_playbackMode == PlaybackMode.sequential) {
        _moveToNextWaypoint();
      } else {
        _statusMessage = "Waypoint completed! Approach another waypoint.";
        _updateMarkers();
      }
    });
  }

  void _moveToNextWaypoint() {
    setState(() {
      _isAudioPlaying = false;
      _currentPointIndex++;

      if (_currentPointIndex >= widget.tour.waypoints.length) {
        _statusMessage = "Tour completed! All ${widget.tour.waypoints.length} waypoints visited.";
        _tourStarted = false;
      } else {
        _statusMessage = "Moving to waypoint ${_currentPointIndex + 1}...";
        _updateMarkers();
        _playCurrentWaypoint();
      }
    });
  }

  void _skipCurrentWaypoint() {
    if (_isAudioPlaying) {
      _audioPlayer.stop();
      _tts.stop();
    }

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Skip Waypoint'),
          content: Text('Skip waypoint ${_currentPointIndex + 1}?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                setState(() {
                  _completedWaypoints.add(_currentPointIndex);
                  _isAudioPlaying = false;
                });

                if (_playbackMode == PlaybackMode.sequential) {
                  _moveToNextWaypoint();
                } else {
                  setState(() {
                    _statusMessage = "Waypoint skipped.";
                    _updateMarkers();
                  });
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
              ),
              child: const Text('Skip'),
            ),
          ],
        );
      },
    );
  }

  @override
  void dispose() {
    _positionStreamSubscription?.cancel();
    _playerStateSubscription?.cancel();
    _audioPlayer.dispose();
    _tts.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.tour.name),
        backgroundColor: Colors.blue,
      ),
      body: Column(
        children: [
          // Mode selection panel (before tour starts)
          if (!_tourStarted)
            Container(
              padding: const EdgeInsets.all(16),
              color: Colors.blue.shade50,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Select Playback Mode:',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () {
                            setState(() {
                              _playbackMode = PlaybackMode.sequential;
                            });
                          },
                          icon: const Icon(Icons.format_list_numbered),
                          label: const Text('Sequential'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _playbackMode == PlaybackMode.sequential
                                ? Colors.blue
                                : Colors.grey.shade300,
                            foregroundColor: _playbackMode == PlaybackMode.sequential
                                ? Colors.white
                                : Colors.black,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () {
                            setState(() {
                              _playbackMode = PlaybackMode.proximity;
                            });
                          },
                          icon: const Icon(Icons.explore),
                          label: const Text('Proximity'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _playbackMode == PlaybackMode.proximity
                                ? Colors.blue
                                : Colors.grey.shade300,
                            foregroundColor: _playbackMode == PlaybackMode.proximity
                                ? Colors.white
                                : Colors.black,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _startTour,
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Start Tour'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // Status bar
          Container(
            padding: const EdgeInsets.all(12),
            color: _isAudioPlaying ? Colors.green.shade100 : Colors.grey.shade200,
            child: Row(
              children: [
                if (_isAudioPlaying)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                if (_isAudioPlaying) const SizedBox(width: 8),
                Expanded(
                  child: Text(_statusMessage, style: const TextStyle(fontSize: 14)),
                ),
                if (_tourStarted)
                  Chip(
                    label: Text(
                      '${_completedWaypoints.length}/${widget.tour.waypoints.length}',
                      style: const TextStyle(fontSize: 12),
                    ),
                    backgroundColor: Colors.blue.shade100,
                  ),
              ],
            ),
          ),

          // Map
          Expanded(
            child: GoogleMap(
              initialCameraPosition: CameraPosition(
                target: widget.tour.waypoints.isNotEmpty
                    ? LatLng(
                        widget.tour.waypoints.first.latitude,
                        widget.tour.waypoints.first.longitude,
                      )
                    : const LatLng(0, 0),
                zoom: 14.0,
              ),
              markers: _markers,
              myLocationEnabled: true,
              myLocationButtonEnabled: true,
              onMapCreated: (GoogleMapController controller) {
                _mapController.complete(controller);
              },
            ),
          ),

          // Control buttons
          if (_tourStarted)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.shade300,
                    blurRadius: 4,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _isAudioPlaying ? _skipCurrentWaypoint : null,
                      icon: const Icon(Icons.skip_next),
                      label: const Text('Skip'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
