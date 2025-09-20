// lib/main.dart (Full Replacement)

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'dart:convert';
import 'tour.dart';
import 'tour_point.dart';
import 'dart:async'; // For StreamSubscription
import 'package:http/http.dart' as http;

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
                  MaterialPageRoute(builder: (context) => const TourListScreen()),
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

// RECORDING SCREEN (No changes from last time)
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
      setState(() { _isPermissionGranted = true; });
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
      Position position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      setState(() {
        _currentPosition = position;
        _locationMessage = "Latitude: ${position.latitude.toStringAsFixed(6)}\nLongitude: ${position.longitude.toStringAsFixed(6)}";
      });
    } catch (e) {
      setState(() { _locationMessage = "Could not get location: $e"; });
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
      _recorderPath = '${appDocumentsDir.path}/audio_${DateTime.now().millisecondsSinceEpoch}.aac';
      await _audioRecorder!.startRecorder(toFile: _recorderPath, codec: Codec.aacADTS);
      setState(() {
        _isRecording = true;
        _recordingIndex = index;
      });
    }
  }

  Future<void> _saveTour(String tourName) async {
    if (tourName.isEmpty) return;
    final tour = Tour(name: tourName, points: _tourPoints);
    final tourJson = jsonEncode(tour.toJson());
    final Directory appDocumentsDir = await getApplicationDocumentsDirectory();
    final String filePath = '${appDocumentsDir.path}/tour_${tourName.replaceAll(' ', '_')}.json';
    final File file = File(filePath);
    await file.writeAsString(tourJson);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Tour "$tourName" saved!')));
    Navigator.of(context).pop();
  }

  void _showSaveDialog() {
    final TextEditingController nameController = TextEditingController();
    showDialog(context: context, builder: (context) {
        return AlertDialog(
          title: const Text('Save Tour'),
          content: TextField(controller: nameController, decoration: const InputDecoration(hintText: "Enter tour name")),
          actions: [
            TextButton(child: const Text('Cancel'), onPressed: () => Navigator.of(context).pop()),
            TextButton(child: const Text('Save'), onPressed: () {
                _saveTour(nameController.text);
                Navigator.of(context).pop();
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
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: _tourPoints.isNotEmpty ? _showSaveDialog : null,
          )
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(children: [
            Text(_locationMessage, textAlign: TextAlign.center, style: const TextStyle(fontSize: 18)),
            const SizedBox(height: 20),
            if (_isPermissionGranted)
              ElevatedButton.icon(
                icon: const Icon(Icons.add_location_alt),
                label: const Text('Add Waypoint'),
                onPressed: _isRecording ? null : _addWaypoint,
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

// NEW TOUR LIST SCREEN
class TourListScreen extends StatefulWidget {
  const TourListScreen({super.key});

  @override
  State<TourListScreen> createState() => _TourListScreenState();
}

class _TourListScreenState extends State<TourListScreen> {
  List<Tour> _tours = [];
  bool _isLoading = true;
  String? _errorMessage;

  // The base URL of your locally running server
  // Use 10.0.2.2 for the Android Emulator
  final String _baseUrl = "http://10.0.2.2:8000";

  @override
  void initState() {
    super.initState();
    _loadToursFromServer();
  }

  Future<void> _loadToursFromServer() async {
    try {
      final response = await http.get(Uri.parse('$_baseUrl/tours'));

      if (response.statusCode == 200) {
        final List<dynamic> tourJsonList = jsonDecode(response.body);
        final List<Tour> loadedTours = tourJsonList.map((json) => Tour.fromJson(json)).toList();

        setState(() {
          _tours = loadedTours;
          _isLoading = false;
        });
      } else {
        setState(() {
          _errorMessage = "Failed to load tours. Status code: ${response.statusCode}";
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = "Failed to connect to the server. Make sure it's running.\nError: $e";
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Select a Tour'),
        backgroundColor: Colors.blueAccent,
        foregroundColor: Colors.white,
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_errorMessage != null) {
      return Center(child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Text(_errorMessage!, textAlign: TextAlign.center),
      ));
    }
    if (_tours.isEmpty) {
      return const Center(child: Text('No tours found on the server.'));
    }

    return ListView.builder(
      itemCount: _tours.length,
      itemBuilder: (context, index) {
        final tour = _tours[index];
        return Card(
          child: ListTile(
            title: Text(tour.name),
            subtitle: Text('${tour.points.length} waypoints'),
            trailing: const Icon(Icons.arrow_forward_ios),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => PlayingScreen(tour: tour),
                ),
              );
            },
          ),
        );
      },
    );
  }
}


// UPDATED PLAYING SCREEN
class PlayingScreen extends StatefulWidget {
  final Tour tour;
  const PlayingScreen({super.key, required this.tour});

  @override
  State<PlayingScreen> createState() => _PlayingScreenState();
}

class _PlayingScreenState extends State<PlayingScreen> {
  // Player and Location state
  FlutterSoundPlayer? _audioPlayer;
  StreamSubscription<Position>? _locationSubscription;

  // Tour state
  final Set<int> _playedIndices = {}; // Keeps track of which waypoints we've already played
  int _nextWaypointIndex = 0;
  String _statusMessage = "Starting tour...";
  double _distanceToNextPoint = -1;

  @override
  void initState() {
    super.initState();
    _audioPlayer = FlutterSoundPlayer();
    _initPlayerAndLocation();
  }

  Future<void> _initPlayerAndLocation() async {
    await _audioPlayer!.openPlayer();
    _startLocationListener();
  }

  void _startLocationListener() {
    const LocationSettings locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 1, // Notify us for every 1 meter of movement
    );

    _locationSubscription = Geolocator.getPositionStream(locationSettings: locationSettings).listen((Position position) {
      print("Current Position: ${position.latitude}, ${position.longitude}");
      _checkForWaypoint(position);
    });

    setState(() {
      _statusMessage = "Walk towards the first waypoint.";
    });
  }

  void _checkForWaypoint(Position currentPosition) {
    if (_nextWaypointIndex >= widget.tour.points.length) {
      setState(() {
        _statusMessage = "Tour complete!";
        _locationSubscription?.cancel(); // Stop listening to location
      });
      return;
    }

    final nextPoint = widget.tour.points[_nextWaypointIndex];

    // Calculate distance between current location and the next waypoint
    final double distance = Geolocator.distanceBetween(
      currentPosition.latitude,
      currentPosition.longitude,
      nextPoint.latitude,
      nextPoint.longitude,
    );

    setState(() {
      _distanceToNextPoint = distance;
    });

    // Check if user is within the trigger radius (e.g., 30 meters)
    if (distance <= 30 && !_playedIndices.contains(_nextWaypointIndex)) {
      _playAudioForWaypoint(_nextWaypointIndex);
    }
  }

  Future<void> _playAudioForWaypoint(int index) async {
    final point = widget.tour.points[index];
    if (point.audioPath != null && await File(point.audioPath!).exists()) {
      setState(() {
        _statusMessage = "Playing audio for waypoint ${index + 1}...";
        _playedIndices.add(index); // Mark as played
      });

      await _audioPlayer!.startPlayer(
        fromURI: point.audioPath,
        whenFinished: () {
          setState(() {
            _nextWaypointIndex++; // Move to the next waypoint
            if (_nextWaypointIndex < widget.tour.points.length) {
              _statusMessage = "Walk towards waypoint ${_nextWaypointIndex + 1}.";
            } else {
              _statusMessage = "Tour complete!";
              _locationSubscription?.cancel();
            }
          });
        },
      );
    } else {
      // Audio file not found, so we skip to the next point
      print("Audio file not found for waypoint $index. Skipping.");
      setState(() {
        _playedIndices.add(index);
        _nextWaypointIndex++;
      });
    }
  }

  @override
  void dispose() {
    _locationSubscription?.cancel();
    _audioPlayer!.closePlayer();
    _audioPlayer = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Playing: ${widget.tour.name}'),
        backgroundColor: Colors.blueAccent,
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              _statusMessage,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 30),
            if (_distanceToNextPoint >= 0 && _nextWaypointIndex < widget.tour.points.length)
              Text(
                "Distance to next waypoint: ${_distanceToNextPoint.toStringAsFixed(0)} meters",
                style: const TextStyle(fontSize: 18),
              ),
          ],
        ),
      ),
    );
  }
}
