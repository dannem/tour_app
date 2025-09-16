// lib/main.dart

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'tour_point.dart';
import 'dart:convert'; // For jsonEncode
import 'tour.dart';    // Our new Tour class

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

  FlutterSoundRecorder? _audioRecorder;
  bool _isRecording = false;
  int? _recordingIndex;
  String? _recorderPath;

  @override
  void initState() {
    super.initState();
    _audioRecorder = FlutterSoundRecorder();
    _initRecorder();
    _requestPermissions();
  }

  @override
  void dispose() {
    _audioRecorder!.closeRecorder();
    _audioRecorder = null;
    super.dispose();
  }

  Future<void> _initRecorder() async {
    await _audioRecorder!.openRecorder();
  }

  Future<void> _requestPermissions() async {
    await Permission.location.request();
    await Permission.microphone.request();

    var locationStatus = await Permission.location.status;

    if (locationStatus.isGranted) {
      setState(() {
        _isPermissionGranted = true;
      });
      _getCurrentLocation();
    } else {
      setState(() {
        _locationMessage = "Location & Mic permissions are required.";
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
      await _audioRecorder!.stopRecorder();
      setState(() {
        _tourPoints[index].audioPath = _recorderPath;
        _isRecording = false;
        _recordingIndex = null;
        _recorderPath = null;
      });
    } else {
      final Directory appDocumentsDir = await getApplicationDocumentsDirectory();
      _recorderPath =
          '${appDocumentsDir.path}/audio_${DateTime.now().millisecondsSinceEpoch}.aac';

      await _audioRecorder!.startRecorder(
        toFile: _recorderPath,
        codec: Codec.aacADTS,
      );

      setState(() {
        _isRecording = true;
        _recordingIndex = index;
      });
    }
  }

  // NEW METHOD to handle saving the tour
  Future<void> _saveTour(String tourName) async {
    if (tourName.isEmpty) return;

    final tour = Tour(name: tourName, points: _tourPoints);
    final tourJson = jsonEncode(tour.toJson());

    final Directory appDocumentsDir = await getApplicationDocumentsDirectory();
    final String filePath = '${appDocumentsDir.path}/tour_$tourName.json';
    final File file = File(filePath);
    await file.writeAsString(tourJson);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Tour "$tourName" saved to $filePath')),
    );

    Navigator.of(context).pop(); // Go back to the home screen
  }

  // NEW METHOD to show the save dialog
  void _showSaveDialog() {
    final TextEditingController nameController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Save Tour'),
          content: TextField(
            controller: nameController,
            decoration: const InputDecoration(hintText: "Enter tour name"),
          ),
          actions: [
            TextButton(
              child: const Text('Cancel'),
              onPressed: () => Navigator.of(context).pop(),
            ),
            TextButton(
              child: const Text('Save'),
              onPressed: () {
                _saveTour(nameController.text);
                Navigator.of(context).pop(); // Close the dialog
              },
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Record Tour'),
        backgroundColor: Colors.blueAccent,
        foregroundColor: Colors.white,
        actions: [ // NEW Save button in the AppBar
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: _tourPoints.isNotEmpty ? _showSaveDialog : null,
          )
        ],
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
                onPressed: _isRecording ? null : _addWaypoint,
              ),
            const SizedBox(height: 20),
            const Text("Waypoints:",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            Expanded(
              child: ListView.builder(
                itemCount: _tourPoints.length,
                itemBuilder: (context, index) {
                  final point = _tourPoints[index];
                  final bool isCurrentlyRecording =
                      _isRecording && _recordingIndex == index;

                  return Card(
                    child: ListTile(
                      leading: Text("${index + 1}",
                          style: const TextStyle(fontSize: 16)),
                      title:
                          Text("Lat: ${point.latitude.toStringAsFixed(4)}"),
                      subtitle:
                          Text("Lon: ${point.longitude.toStringAsFixed(4)}"),
                      trailing: point.audioPath != null
                          ? const Icon(Icons.check_circle,
                              color: Colors.green)
                          : IconButton(
                              icon: Icon(isCurrentlyRecording
                                  ? Icons.stop
                                  : Icons.mic),
                              color: isCurrentlyRecording
                                  ? Colors.red
                                  : Colors.black,
                              onPressed: _isRecording && !isCurrentlyRecording
                                  ? null
                                  : () => _toggleRecording(index),
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
