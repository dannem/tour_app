import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:geocoding/geocoding.dart';
import 'package:intl/intl.dart';
import 'dart:convert';
import 'dart:async';
// import 'dart:io';

// --- Server URL ---
const String serverBaseUrl = "https://tour-app-server.onrender.com";
// --------------------

void main() {
  runApp(const TourApp());
}

// --- Data Models and API Service ---

class TourPoint {
  final int id;
  final double latitude;
  final double longitude;
  final String audioFilePath;
  final String? localAudioPath;
  final String? name; // Added a name for waypoints

  TourPoint({
    required this.id,
    required this.latitude,
    required this.longitude,
    required this.audioFilePath,
    this.localAudioPath,
    this.name,
  });

  factory TourPoint.fromJson(Map<String, dynamic> json) {
    return TourPoint(
      id: json['id'],
      latitude: json['latitude'],
      longitude: json['longitude'],
      audioFilePath: json['audio_filename'],
      name: json['name'], // Assuming server might send a name
    );
  }
}

class Tour {
  final int id;
  final String title;
  final String description;
  final List<TourPoint> points;

  Tour({
    required this.id,
    required this.title,
    required this.description,
    required this.points,
  });

  factory Tour.fromJson(Map<String, dynamic> json) {
    var pointsList = json['waypoints'] as List? ?? [];
    List<TourPoint> tourPoints = pointsList.map((i) => TourPoint.fromJson(i)).toList();
    return Tour(
      id: json['id'],
      title: json['name'],
      description: json['description'],
      points: tourPoints,
    );
  }
}

class ApiService {
  Future<List<Tour>> fetchTours() async {
    try {
      final response = await http.get(Uri.parse('$serverBaseUrl/tours/'));
      if (response.statusCode == 200) {
        List<dynamic> toursJson = json.decode(response.body);
        return toursJson.map((json) => Tour.fromJson(json)).toList();
      } else {
        throw Exception('Failed to load tours from server (Status code: ${response.statusCode})');
      }
    } catch (e) {
      throw Exception('Could not connect to server or parse tours. Error: $e');
    }
  }

  Future<Tour> fetchTourDetails(int tourId) async {
     try {
      final response = await http.get(Uri.parse('$serverBaseUrl/tours/$tourId'));
      if (response.statusCode == 200) {
        return Tour.fromJson(json.decode(response.body));
      } else {
        throw Exception('Failed to load tour details (Status code: ${response.statusCode})');
      }
    } catch (e) {
      throw Exception('Could not connect to server or parse tour details. Error: $e');
    }
  }

  Future<Tour> createTour(String name, String description) async {
    final response = await http.post(
      Uri.parse('$serverBaseUrl/tours/'),
      headers: <String, String>{
        'Content-Type': 'application/json; charset=UTF-8',
      },
      body: jsonEncode(<String, String>{
        'name': name,
        'description': description,
      }),
    );
    if (response.statusCode == 200) {
      return Tour.fromJson(jsonDecode(response.body));
    } else {
      throw Exception('Failed to create tour.');
    }
  }

  Future<void> createWaypoint({
    required int tourId,
    required String name,
    required double latitude,
    required double longitude,
    required String audioFilePath,
  }) async {
    var request = http.MultipartRequest(
      'POST',
      Uri.parse('$serverBaseUrl/tours/$tourId/waypoints/'),
    );
    request.fields['name'] = name; // Add name to the request
    request.fields['latitude'] = latitude.toString();
    request.fields['longitude'] = longitude.toString();
    request.files.add(
      await http.MultipartFile.fromPath('audio_file', audioFilePath),
    );
    var response = await request.send();
    if (response.statusCode != 200) {
      final responseBody = await response.stream.bytesToString();
      throw Exception('Failed to upload waypoint. Server responded with: $responseBody');
    }
  }
}

// --- App Main Widget ---

class TourApp extends StatelessWidget {
  const TourApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Tour App',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: const ChoiceScreen(),
    );
  }
}

// --- Main Screens ---

class ChoiceScreen extends StatelessWidget {
  const ChoiceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tour App'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: ElevatedButton.icon(
                icon: const Icon(Icons.play_arrow),
                label: const Text('Play Tour'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  textStyle: const TextStyle(fontSize: 18),
                  backgroundColor: Colors.blue,
                ),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const TourListScreen()),
                  );
                },
              ),
            ),
            const Divider(height: 20, thickness: 1, indent: 20, endIndent: 20),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: ElevatedButton.icon(
                icon: const Icon(Icons.map),
                label: const Text('Manual Recording'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  textStyle: const TextStyle(fontSize: 18),
                ),
                onPressed: () {
                   ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Manual Recording not implemented yet.')));
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: ElevatedButton.icon(
                icon: const Icon(Icons.location_on),
                label: const Text('Record a New Tour'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  textStyle: const TextStyle(fontSize: 18),
                ),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const NameTourScreen()),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class NameTourScreen extends StatefulWidget {
  const NameTourScreen({super.key});

  @override
  State<NameTourScreen> createState() => _NameTourScreenState();
}

class _NameTourScreenState extends State<NameTourScreen> {
  late final TextEditingController _nameController;

  @override
  void initState() {
    super.initState();
    String defaultName = "New Tour - ${DateFormat.yMMMd().format(DateTime.now())}";
    _nameController = TextEditingController(text: defaultName);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create New Tour'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text("What is the name of your tour?", style: TextStyle(fontSize: 22)),
            const SizedBox(height: 20),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Tour Name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 30),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 50, vertical: 15),
                textStyle: const TextStyle(fontSize: 18),
              ),
              onPressed: () {
                 if (_nameController.text.isNotEmpty) {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                        builder: (context) => AddWaypointsScreen(tourName: _nameController.text),
                      ),
                    );
                 }
              },
              child: const Text('Continue'),
            )
          ],
        ),
      ),
    );
  }
}

class AddWaypointsScreen extends StatefulWidget {
  final String tourName;
  const AddWaypointsScreen({super.key, required this.tourName});

  @override
  State<AddWaypointsScreen> createState() => _AddWaypointsScreenState();
}

class _AddWaypointsScreenState extends State<AddWaypointsScreen> {
  final List<TourPoint> _newWaypoints = [];
  bool _isUploading = false;
  String _uploadStatus = '';

  void _finishAndSaveTour() {
    final descriptionController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Add Description & Save'),
          content: TextField(
            controller: descriptionController,
            decoration: const InputDecoration(labelText: 'Tour Description'),
            maxLines: 3,
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                _uploadTour(descriptionController.text);
              },
              child: const Text('Save Tour'),
            ),
          ],
        );
      },
    );
  }

  void _uploadTour(String description) async {
    if (description.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Description cannot be empty.')),
      );
      return;
    }

    setState(() {
      _isUploading = true;
      _uploadStatus = 'Creating tour on server...';
    });

    try {
      final newTour = await ApiService().createTour(widget.tourName, description);

      for (int i = 0; i < _newWaypoints.length; i++) {
        final point = _newWaypoints[i];
        setState(() {
          _uploadStatus = 'Uploading waypoint ${i + 1} of ${_newWaypoints.length}...';
        });
        await ApiService().createWaypoint(
          tourId: newTour.id,
          name: point.name!,
          latitude: point.latitude,
          longitude: point.longitude,
          audioFilePath: point.localAudioPath!,
        );
      }

      setState(() {
        _uploadStatus = 'Upload complete!';
        _isUploading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('New tour saved successfully!'), backgroundColor: Colors.green),
      );
      Navigator.of(context).pop();

    } catch (e) {
      setState(() {
        _uploadStatus = 'Error during upload: $e';
        _isUploading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    }
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Recording: ${widget.tourName}'),
        actions: [
          if (_newWaypoints.isNotEmpty && !_isUploading)
            IconButton(
              icon: const Icon(Icons.check_circle),
              onPressed: _finishAndSaveTour,
              tooltip: 'Finish & Save Tour',
            )
        ],
      ),
      body: _isUploading
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 20),
                  Text(_uploadStatus),
                ],
              ),
            )
          : _newWaypoints.isEmpty
              ? const Center(
                  child: Text(
                    'No waypoints added yet.\nPress the + button to add your first one!',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 18, color: Colors.grey),
                  ),
                )
              : ListView.builder(
                  itemCount: _newWaypoints.length,
                  itemBuilder: (context, index) {
                    final point = _newWaypoints[index];
                    return ListTile(
                      leading: CircleAvatar(child: Text('${index + 1}')),
                      title: Text(point.name ?? 'Unnamed Waypoint'),
                      subtitle: Text('Lat: ${point.latitude.toStringAsFixed(4)}, Lon: ${point.longitude.toStringAsFixed(4)}'),
                      trailing: const Icon(Icons.mic),
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final newPoint = await Navigator.push<TourPoint>(
            context,
            MaterialPageRoute(builder: (context) => const EditWaypointScreen()),
          );

          if (newPoint != null) {
            setState(() {
              _newWaypoints.add(newPoint);
            });
          }
        },
        tooltip: 'Add New Waypoint',
        child: const Icon(Icons.add),
      ),
    );
  }
}

class EditWaypointScreen extends StatefulWidget {
  const EditWaypointScreen({super.key});

  @override
  State<EditWaypointScreen> createState() => _EditWaypointScreenState();
}

class _EditWaypointScreenState extends State<EditWaypointScreen> {
  final _nameController = TextEditingController();
  final FlutterSoundRecorder _recorder = FlutterSoundRecorder();

  String _status = 'Getting location...';
  Position? _position;
  bool _isRecorderReady = false;
  bool _isRecording = false;
  String? _recordedFilePath;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    await Permission.microphone.request();
    await Permission.location.request();

    await _recorder.openRecorder();
    setState(() => _isRecorderReady = true);

    try {
      _position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      List<Placemark> placemarks = await placemarkFromCoordinates(_position!.latitude, _position!.longitude);
      if (placemarks.isNotEmpty) {
        final placemark = placemarks.first;
        _nameController.text = "${placemark.street}, ${placemark.locality}";
      } else {
        _nameController.text = "Waypoint at ${_position!.latitude.toStringAsFixed(4)}";
      }
      setState(() => _status = 'Location found. Ready to record audio.');
    } catch (e) {
      setState(() => _status = 'Could not get location. Please try again.');
    }
  }

  void _toggleRecording() async {
    if (!_isRecorderReady) return;

    if (_isRecording) {
      final path = await _recorder.stopRecorder();
      setState(() {
        _recordedFilePath = path;
        _isRecording = false;
        _status = 'Audio recorded! Press Save.';
      });
    } else {
      _recordedFilePath = null;
      await _recorder.startRecorder(toFile: 'audio_${DateTime.now().millisecondsSinceEpoch}.aac');
      setState(() {
        _isRecording = true;
        _status = 'Recording audio...';
      });
    }
  }

  void _saveWaypoint() {
    if (_position == null || _recordedFilePath == null || _nameController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please provide a name, location, and recorded audio before saving.')),
      );
      return;
    }

    final newPoint = TourPoint(
      id: 0,
      name: _nameController.text,
      latitude: _position!.latitude,
      longitude: _position!.longitude,
      audioFilePath: '',
      localAudioPath: _recordedFilePath!,
    );
    Navigator.pop(context, newPoint);
  }

  @override
  void dispose() {
    _recorder.closeRecorder();
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create New Waypoint'),
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: _saveWaypoint,
            tooltip: 'Save Waypoint',
          )
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(_status, style: const TextStyle(color: Colors.grey)),
            const SizedBox(height: 10),
            if (_position != null)
              Text('Lat: ${_position!.latitude.toStringAsFixed(4)}, Lon: ${_position!.longitude.toStringAsFixed(4)}'),
            const SizedBox(height: 20),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Waypoint Name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 30),
            ElevatedButton.icon(
              icon: Icon(_isRecording ? Icons.stop : Icons.mic),
              label: Text(_isRecording ? 'Stop Recording' : 'Record Audio'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _isRecording ? Colors.red : Colors.green,
                padding: const EdgeInsets.symmetric(vertical: 15),
              ),
              onPressed: _isRecorderReady && _position != null ? _toggleRecording : null,
            ),
            if (_recordedFilePath != null && !_isRecording)
              Padding(
                padding: const EdgeInsets.only(top: 10.0),
                child: Text('Audio saved successfully!', textAlign: TextAlign.center, style: TextStyle(color: Colors.green[700])),
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
  late Future<List<Tour>> futureTours;

  @override
  void initState() {
    super.initState();
    futureTours = ApiService().fetchTours();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Select a Tour'),
      ),
      body: FutureBuilder<List<Tour>>(
        future: futureTours,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          } else if (snapshot.hasError) {
            return Center(child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text('Error: ${snapshot.error}', textAlign: TextAlign.center),
            ));
          } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text('No tours found on the server.'));
          } else {
            List<Tour> tours = snapshot.data!;
            return ListView.builder(
              itemCount: tours.length,
              itemBuilder: (context, index) {
                return ListTile(
                  title: Text(tours[index].title),
                  subtitle: Text(tours[index].description),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => TourPlaybackScreen(tourId: tours[index].id),
                      ),
                    );
                  },
                );
              },
            );
          }
        },
      ),
    );
  }
}

class TourPlaybackScreen extends StatefulWidget {
  final int tourId;
  const TourPlaybackScreen({super.key, required this.tourId});

  @override
  State<TourPlaybackScreen> createState() => _TourPlaybackScreenState();
}

class _TourPlaybackScreenState extends State<TourPlaybackScreen> {
  final Completer<GoogleMapController> _mapController = Completer();
  final AudioPlayer _audioPlayer = AudioPlayer();
  StreamSubscription<Position>? _positionStreamSubscription;
  StreamSubscription? _playerStateSubscription;

  Tour? _tour;
  Set<Marker> _markers = {};
  int _currentPointIndex = 0;
  String _statusMessage = 'Loading tour...';
  bool _isAudioPlaying = false;

  @override
  void initState() {
    super.initState();
    _loadTourDetails();
    _playerStateSubscription = _audioPlayer.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            setState(() {
              _isAudioPlaying = false;
              _currentPointIndex++;
              if (_currentPointIndex >= (_tour?.points.length ?? 0)) {
                _statusMessage = "Tour completed!";
                _positionStreamSubscription?.cancel();
              } else {
                _statusMessage = "Audio finished. Walk to the next point.";
                if (_tour != null) {
                  _goToPoint(_tour!.points[_currentPointIndex]);
                }
              }
            });
          }
        });
      }
    });
  }

  Future<void> _loadTourDetails() async {
    try {
      final tour = await ApiService().fetchTourDetails(widget.tourId);
      if (!mounted) return;
      setState(() {
        _tour = tour;
        _statusMessage = 'Tour loaded. Waiting for location...';
        _markers = tour.points.map((point) {
          return Marker(
            markerId: MarkerId(point.id.toString()),
            position: LatLng(point.latitude, point.longitude),
            infoWindow: InfoWindow(title: 'Point ${point.id}'),
          );
        }).toSet();
      });
      if (tour.points.isNotEmpty) {
        _goToPoint(tour.points.first);
      }
      _startLocationListener();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _statusMessage = "Error loading tour: $e";
      });
    }
  }

  Future<void> _goToPoint(TourPoint point) async {
    final GoogleMapController controller = await _mapController.future;
    controller.animateCamera(CameraUpdate.newCameraPosition(
      CameraPosition(
        target: LatLng(point.latitude, point.longitude),
        zoom: 16.0,
      )
    ));
  }


  Future<void> _startLocationListener() async {
    await _determinePosition();
    _positionStreamSubscription = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 10)
    ).listen((Position position) {
      if (!mounted || _tour == null || _currentPointIndex >= _tour!.points.length) {
        return;
      }

      final currentTargetPoint = _tour!.points[_currentPointIndex];
      final distanceInMeters = Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        currentTargetPoint.latitude,
        currentTargetPoint.longitude,
      );

      setState(() {
        if (!_isAudioPlaying) {
          _statusMessage = "You are ${distanceInMeters.toStringAsFixed(0)} meters away from Point ${_currentPointIndex + 1}";
        }
      });

      if (distanceInMeters < 25 && !_isAudioPlaying) {
        _playAudioForPoint(currentTargetPoint);
      }
    });
  }

  Future<void> _playAudioForPoint(TourPoint point) async {
    setState(() {
      _isAudioPlaying = true;
      _statusMessage = "Playing audio for Point ${_currentPointIndex + 1}";
    });

    try {
      final audioUrl = '$serverBaseUrl/${point.audioFilePath}';
      await _audioPlayer.setUrl(audioUrl);
      _audioPlayer.play();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _statusMessage = "Error playing audio: $e";
        _isAudioPlaying = false;
      });
    }
  }

  @override
  void dispose() {
    _positionStreamSubscription?.cancel();
    _playerStateSubscription?.cancel();
    _audioPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_tour?.title ?? 'Loading Tour...'),
      ),
      body: Stack(
        children: [
          GoogleMap(
            onMapCreated: (controller) => _mapController.complete(controller),
            initialCameraPosition: const CameraPosition(target: LatLng(0, 0), zoom: 14),
            markers: _markers,
            myLocationEnabled: true,
            myLocationButtonEnabled: true,
          ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.all(12),
              color: Colors.white.withOpacity(0.9),
              child: Text(
                _statusMessage,
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _determinePosition() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (!mounted) return;
      setState(() => _statusMessage = 'Location services are disabled.');
      return;
    }
    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        if (!mounted) return;
        setState(() => _statusMessage = 'Location permissions are denied.');
        return;
      }
    }
    if (permission == LocationPermission.deniedForever) {
      if (!mounted) return;
      setState(() => _statusMessage = 'Location permissions are permanently denied.');
      return;
    }
  }
}

class MapScreen extends StatelessWidget {
  const MapScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Manual Recording')),
      body: const Center(child: Text('Manual Recording UI goes here.')),
    );
  }
}
