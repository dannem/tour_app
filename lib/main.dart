// lib/main.dart

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'dart:async';
import 'tour.dart';
import 'tour_point.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as path;

const String baseUrl = "https://tour-app-server.onrender.com";

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
  bool _isSaving = false;

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

  // NEW FUNCTION: Add a waypoint from a manually provided address or coordinates
  void _addWaypointFromHome() {
    final _addressController = TextEditingController();
    final _latController = TextEditingController();
    final _lonController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Add Waypoint Manually'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: _addressController,
                  decoration: const InputDecoration(labelText: 'Address'),
                ),
                const SizedBox(height: 10),
                const Text('OR'),
                const SizedBox(height: 10),
                TextField(
                  controller: _latController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Latitude'),
                ),
                TextField(
                  controller: _lonController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Longitude'),
                ),
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  onPressed: () async {
                    FilePickerResult? result = await FilePicker.platform.pickFiles(
                      type: FileType.custom,
                      allowedExtensions: ['aac', 'mp3', 'm4a'],
                    );
                    if (result != null) {
                      final audioFile = File(result.files.single.path!);
                      _addManualWaypoint(
                        address: _addressController.text.trim(),
                        latitude: double.tryParse(_latController.text.trim()),
                        longitude: double.tryParse(_lonController.text.trim()),
                        audioFile: audioFile,
                      );
                      Navigator.of(context).pop();
                    }
                  },
                  icon: const Icon(Icons.upload_file),
                  label: const Text('Upload Audio File'),
                ),
                const SizedBox(height: 10),
                ElevatedButton.icon(
                  onPressed: () {
                    _addManualWaypoint(
                      address: _addressController.text.trim(),
                      latitude: double.tryParse(_latController.text.trim()),
                      longitude: double.tryParse(_lonController.text.trim()),
                    );
                    Navigator.of(context).pop();
                  },
                  icon: const Icon(Icons.mic),
                  label: const Text('Record Audio Later'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // NEW FUNCTION: Add the waypoint to the list
  void _addManualWaypoint({
    String? address,
    double? latitude,
    double? longitude,
    File? audioFile,
  }) {
    setState(() {
      _tourPoints.add(TourPoint(
        latitude: latitude ?? 0,
        longitude: longitude ?? 0,
        audioPath: audioFile?.path,
      ));
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Waypoint added to the list. Press save when finished.')),
    );
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

    setState(() {
      _isSaving = true;
    });

    try {
      final tourCreateResponse = await http.post(
        Uri.parse('$baseUrl/tours'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'name': tourName, 'description': 'A new tour created from the app.'}),
      );

      if (tourCreateResponse.statusCode != 201) {
        throw Exception('Failed to create tour. Status: ${tourCreateResponse.statusCode}');
      }

      final newTour = jsonDecode(tourCreateResponse.body);
      final int tourId = newTour['id'];

      for (var point in _tourPoints) {
        if (point.audioPath == null) continue;

        var request = http.MultipartRequest(
          'POST',
          Uri.parse('$baseUrl/tours/$tourId/waypoints'),
        );

        // Use a new endpoint for manual waypoints
        final url = Uri.parse('$baseUrl/tours/$tourId/waypoints/from_home');
        var manualRequest = http.MultipartRequest('POST', url);

        if (point.audioPath != null) {
          manualRequest.files.add(await http.MultipartFile.fromPath(
            'audio_file',
            point.audioPath!,
            filename: path.basename(point.audioPath!),
          ));
        }

        manualRequest.fields['latitude'] = point.latitude.toString();
        manualRequest.fields['longitude'] = point.longitude.toString();

        final response = await manualRequest.send();
        if (response.statusCode != 200) {
          throw Exception('Failed to upload waypoint. Status: ${response.statusCode}');
        }
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Tour "$tourName" successfully uploaded!')),
      );
      Navigator.of(context).pop();

    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('An error occurred: $e')),
      );
    } finally {
      setState(() {
        _isSaving = false;
      });
    }
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
            onPressed: _tourPoints.isNotEmpty && !_isSaving ? _showSaveDialog : null,
          )
        ],
      ),
      body: _isSaving
          ? const Center(child: CircularProgressIndicator())
          : Padding(
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
            ElevatedButton.icon(
              icon: const Icon(Icons.home),
              label: const Text('Add Waypoint Manually'),
              onPressed: _isRecording ? null : _addWaypointFromHome,
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

class TourListScreen extends StatefulWidget {
  const TourListScreen({super.key});

  @override
  State<TourListScreen> createState() => _TourListScreenState();
}

class _TourListScreenState extends State<TourListScreen> {
  List<Tour> _tours = [];
  bool _isLoading = true;
  String? _errorMessage;
  bool _isDownloading = false;

  @override
  void initState() {
    super.initState();
    _loadToursFromServer();
  }

  Future<void> _loadToursFromServer() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/tours'));

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

  Future<void> _downloadAndStartTour(Tour tour) async {
    setState(() {
      _isDownloading = true;
    });

    try {
      final tempDir = await getTemporaryDirectory();

      for (var waypoint in tour.waypoints) {
        if (waypoint.audio_filename != null) {
          final url = '$baseUrl/uploads/${waypoint.audio_filename}';
          final response = await http.get(Uri.parse(url));

          if (response.statusCode == 200) {
            if (response.bodyBytes.isEmpty) {
              print('Error: Downloaded file for ${waypoint.audio_filename} is empty.');
              continue;
            }

            final file = File('${tempDir.path}/${waypoint.audio_filename}');
            await file.writeAsBytes(response.bodyBytes);
            waypoint.audioPath = file.path;
          } else {
            print('Failed to download audio file: ${waypoint.audio_filename}');
          }
        }
      }

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => PlayingScreen(tour: tour),
        ),
      );

    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to download tour audio: $e')),
      );
    } finally {
      setState(() {
        _isDownloading = false;
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
      body: Stack(
        children: [
          _buildBody(),
          if (_isDownloading)
            const Center(
              child: Card(
                color: Colors.white,
                child: Padding(
                  padding: EdgeInsets.all(20.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 10),
                      Text("Downloading audio..."),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
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
            subtitle: Text('${tour.waypoints.length} waypoints'),
            trailing: const Icon(Icons.arrow_forward_ios),
            onTap: () => _downloadAndStartTour(tour),
          ),
        );
      },
    );
  }
}

class PlayingScreen extends StatefulWidget {
  final Tour tour;
  const PlayingScreen({super.key, required this.tour});

  @override
  State<PlayingScreen> createState() => _PlayingScreenState();
}

class _PlayingScreenState extends State<PlayingScreen> {
  FlutterSoundPlayer? _audioPlayer;
  StreamSubscription<Position>? _locationSubscription;

  final Set<int> _playedIndices = {};
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
      distanceFilter: 1,
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
    if (widget.tour.waypoints.isEmpty) {
        setState(() {
          _statusMessage = "This tour has no waypoints.";
          _locationSubscription?.cancel();
        });
        return;
      }
    if (_nextWaypointIndex >= widget.tour.waypoints.length) {
      setState(() {
        _statusMessage = "Tour complete!";
        _locationSubscription?.cancel();
      });
      return;
    }

    final nextPoint = widget.tour.waypoints[_nextWaypointIndex];

    final double distance = Geolocator.distanceBetween(
      currentPosition.latitude,
      currentPosition.longitude,
      nextPoint.latitude,
      nextPoint.longitude,
    );

    setState(() {
      _distanceToNextPoint = distance;
    });

    if (distance <= 30 && !_playedIndices.contains(_nextWaypointIndex)) {
      _playAudioForWaypoint(_nextWaypointIndex);
    }
  }

  Future<void> _playAudioForWaypoint(int index) async {
    final point = widget.tour.waypoints[index];

    if (point.audioPath == null || !(await File(point.audioPath!).exists())) {
      print("Audio file not found for waypoint $index. Skipping.");
      setState(() {
        _playedIndices.add(index);
        _nextWaypointIndex++;
      });
      return;
    }

    try {
      setState(() {
        _statusMessage = "Playing audio for waypoint ${index + 1}...";
        _playedIndices.add(index);
      });

      await _audioPlayer!.startPlayer(
        fromURI: point.audioPath,
        whenFinished: () {
          setState(() {
            _nextWaypointIndex++;
            if (_nextWaypointIndex < widget.tour.waypoints.length) {
              _statusMessage = "Walk towards waypoint ${_nextWaypointIndex + 1}.";
            } else {
              _statusMessage = "Tour complete!";
              _locationSubscription?.cancel();
            }
          });
        },
      );
    } catch (e) {
      print("Error during startPlayer: $e");
      setState(() {
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
            if (_distanceToNextPoint >= 0 && _nextWaypointIndex < widget.tour.waypoints.length)
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
