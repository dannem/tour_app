import 'browse_tours_screen.dart';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'tour_models.dart'; // Import the models you just created

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

// The main screen with buttons to record or play a tour
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tour App'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton(
              onPressed: () {
                // Add this button to navigate to your new screen
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const BrowseToursScreen()),
                );
              },
              child: const Text('Browse Server Tours'),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const RecordingScreen()),
                );
              },
              child: const Text('Record a New Tour'),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const PlayingScreen()),
                );
              },
              child: const Text('Play a Local Tour'),
            ),
          ],
        ),
      ),
    );
  }
}

// The screen for recording a new tour
class RecordingScreen extends StatefulWidget {
  const RecordingScreen({super.key});

  @override
  State<RecordingScreen> createState() => _RecordingScreenState();
}

class _RecordingScreenState extends State<RecordingScreen> {
  final List<TourPoint> _tourPoints = [];
  final TextEditingController _tourNameController = TextEditingController();

  // Function to request necessary permissions
  Future<void> _requestPermissions() async {
    await Permission.location.request();
    await Permission.storage.request(); // Needed for saving files
    // You might also need microphone permission if you add audio recording
    // await Permission.microphone.request();
  }

  // Function to get the current GPS location
  Future<void> _addWaypoint() async {
    await _requestPermissions();
    try {
      Position position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);

      // For this demo, we'll use a placeholder for the audio path.
      // In a real app, you would implement audio recording logic here.
      String audioPath = 'path/to/your/recorded/audio${_tourPoints.length + 1}.mp3';

      setState(() {
        _tourPoints.add(TourPoint(
            latitude: position.latitude,
            longitude: position.longitude,
            audioPath: audioPath));
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Waypoint added at ${position.latitude}, ${position.longitude}')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to get location: $e')),
      );
    }
  }

  // Function to save the tour to a JSON file
  Future<void> _saveTour() async {
    if (_tourNameController.text.isEmpty || _tourPoints.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Please enter a tour name and add at least one waypoint.')),
      );
      return;
    }

    final tour = Tour(name: _tourNameController.text, points: _tourPoints);
    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/${_tourNameController.text.replaceAll(' ', '_')}.json');
    await file.writeAsString(jsonEncode(tour.toJson()));

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Tour saved to ${file.path}')),
    );

    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Record Tour'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: _tourNameController,
              decoration: const InputDecoration(labelText: 'Tour Name'),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _addWaypoint,
              child: const Text('Add Waypoint'),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: ListView.builder(
                itemCount: _tourPoints.length,
                itemBuilder: (context, index) {
                  final point = _tourPoints[index];
                  return ListTile(
                    title: Text('Waypoint ${index + 1}'),
                    subtitle: Text('Lat: ${point.latitude.toStringAsFixed(4)}, Lon: ${point.longitude.toStringAsFixed(4)}'),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _saveTour,
        child: const Icon(Icons.save),
      ),
    );
  }
}

// The screen for playing a saved tour
class PlayingScreen extends StatefulWidget {
  const PlayingScreen({super.key});

  @override
  State<PlayingScreen> createState() => _PlayingScreenState();
}

class _PlayingScreenState extends State<PlayingScreen> {
  Tour? _currentTour;
  final AudioPlayer _audioPlayer = AudioPlayer();
  final Set<String> _playedAudioPaths = {};

  @override
  void initState() {
    super.initState();
    _loadTourAndStartGps();
  }

  // Load the tour from the JSON file and start listening to GPS
  Future<void> _loadTourAndStartGps() async {
    // For this demo, we'll load a hardcoded tour name.
    // In a real app, you would show a list of saved tours for the user to pick.
    const tourName = "My_First_Tour"; // Make sure this matches the name you save

    try {
        final directory = await getApplicationDocumentsDirectory();
        final file = File('${directory.path}/$tourName.json');
        final contents = await file.readAsString();
        setState(() {
            _currentTour = Tour.fromJson(jsonDecode(contents));
        });

        // Start listening to location changes
        Geolocator.getPositionStream().listen((Position position) {
            _checkWaypoints(position);
        });
    } catch (e) {
        // Handle error, e.g., file not found
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Could not load tour: $tourName.json. Make sure you've saved a tour with that exact name.")),
        );
    }
  }


  // Check the user's current location against the tour's waypoints
  void _checkWaypoints(Position currentPosition) {
    if (_currentTour == null) return;

    for (final point in _currentTour!.points) {
      final distance = Geolocator.distanceBetween(
        currentPosition.latitude,
        currentPosition.longitude,
        point.latitude,
        point.longitude,
      );

      // If within 20 meters and not already played, play the audio
      if (distance < 20 && !_playedAudioPaths.contains(point.audioPath)) {
        // In a real app, you'd play the actual audio file.
        // For now, we'll just show a notification.
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Playing audio for waypoint at ${point.latitude}, ${point.longitude}')),
        );
        _playedAudioPaths.add(point.audioPath);

        // This is where you would use the just_audio package to play the file:
        // _audioPlayer.setFilePath(point.audioPath);
        // _audioPlayer.play();
      }
    }
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_currentTour?.name ?? 'Playing Tour...'),
      ),
      body: Center(
        child: _currentTour == null
            ? const CircularProgressIndicator()
            : const Text('Walking tour in progress...'),
      ),
    );
  }
}
