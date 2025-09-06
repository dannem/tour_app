// lib/main.dart

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:geolocator/geolocator.dart';
import 'tour_point.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Tour App',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blueAccent),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tour App'),
        backgroundColor: Colors.blueAccent,
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            ElevatedButton.icon(
              icon: const Icon(Icons.mic),
              label: const Text('Record a New Tour'),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const RecordingScreen()),
                );
              },
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                textStyle: const TextStyle(fontSize: 18),
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              icon: const Icon(Icons.play_arrow),
              label: const Text('Play an Existing Tour'),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const PlayingScreen()),
                );
              },
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                textStyle: const TextStyle(fontSize: 18),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class RecordingScreen extends StatefulWidget {
  const RecordingScreen({super.key});

  @override
  State<RecordingScreen> createState() => _RecordingScreenState();
}

class _RecordingScreenState extends State<RecordingScreen> {
  String _locationMessage = "Getting location...";
  bool _isPermissionGranted = false;
  Position? _currentPosition;

  final List<TourPoint> _tourPoints = [];

  // Audio recording state
  final AudioRecorder _audioRecorder = AudioRecorder();
  bool _isRecording = false;
  int? _recordingIndex; // To track which waypoint is being recorded

  @override
  void initState() {
    super.initState();
    _requestLocationPermission();
  }

  @override
  void dispose() {
    _audioRecorder.dispose(); // Clean up the recorder
    super.dispose();
  }

  Future<void> _requestLocationPermission() async {
    await Permission.location.request();
    await Permission.microphone.request(); // Also request microphone permission

    var locationStatus = await Permission.location.status;

    if (locationStatus.isGranted) {
      setState(() {
        _isPermissionGranted = true;
      });
      _getCurrentLocation();
    } else {
      setState(() {
        _locationMessage = "Location permission is required to record a tour.";
        _isPermissionGranted = false;
      });
    }
  }

  Future<void> _getCurrentLocation() async {
    try {
      Position position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);
      setState(() {
        _currentPosition = position;
        _locationMessage =
            "Latitude: ${position.latitude.toStringAsFixed(6)}\nLongitude: ${position.longitude.toStringAsFixed(6)}";
      });
    } catch (e) {
      setState(() {
        _locationMessage = "Could not get location: $e";
      });
    }
  }

  void _addWaypoint() {
    _getCurrentLocation().then((_) {
      if (_currentPosition != null) {
        setState(() {
          _tourPoints.add(TourPoint(
            latitude: _currentPosition!.latitude,
            longitude: _currentPosition!.longitude,
          ));
        });
      }
    });
  }

  Future<void> _toggleRecording(int index) async {
    if (_isRecording) {
      // Stop recording
      final path = await _audioRecorder.stop();
      setState(() {
        _tourPoints[index].audioPath = path;
        _isRecording = false;
        _recordingIndex = null;
      });
    } else {
      // Start recording
      final Directory appDocumentsDir = await getApplicationDocumentsDirectory();
      final String filePath = '${appDocumentsDir.path}/audio_${DateTime.now().millisecondsSinceEpoch}.m4a';

      if (await _audioRecorder.hasPermission()) {
        await _audioRecorder.start(const RecordConfig(), path: filePath);
        setState(() {
          _isRecording = true;
          _recordingIndex = index;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Record Tour'),
        backgroundColor: Colors.blueAccent,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Text(
              _locationMessage,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18),
            ),
            const SizedBox(height: 20),
            if (_isPermissionGranted)
              ElevatedButton.icon(
                icon: const Icon(Icons.add_location_alt),
                label: const Text('Add Waypoint'),
                onPressed: _isRecording ? null : _addWaypoint, // Disable while recording
              ),
            const SizedBox(height: 20),
            const Text("Waypoints:", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            Expanded(
              child: ListView.builder(
                itemCount: _tourPoints.length,
                itemBuilder: (context, index) {
                  final point = _tourPoints[index];
                  final bool isCurrentlyRecording = _isRecording && _recordingIndex == index;

                  return Card(
                    child: ListTile(
                      leading: Text("${index + 1}", style: const TextStyle(fontSize: 16)),
                      title: Text("Lat: ${point.latitude.toStringAsFixed(4)}"),
                      subtitle: Text("Lon: ${point.longitude.toStringAsFixed(4)}"),
                      trailing: point.audioPath != null
                          ? const Icon(Icons.check_circle, color: Colors.green)
                          : IconButton(
                              icon: Icon(isCurrentlyRecording ? Icons.stop : Icons.mic),
                              color: isCurrentlyRecording ? Colors.red : Colors.black,
                              onPressed: _isRecording && !isCurrentlyRecording ? null : () => _toggleRecording(index),
                            ),
                    ),
                  );
                },
              ),
            )
          ],
        ),
      ),
    );
  }
}

class PlayingScreen extends StatefulWidget {
  const PlayingScreen({super.key});

  @override
  State<PlayingScreen> createState() => _PlayingScreenState();
}

class _PlayingScreenState extends State<PlayingScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Play Tour'),
        backgroundColor: Colors.blueAccent,
        foregroundColor: Colors.white,
      ),
      body: const Center(
        child: Text(
          'Tour playback functionality will be implemented here.',
          style: TextStyle(fontSize: 16),
        ),
      ),
    );
  }
}
