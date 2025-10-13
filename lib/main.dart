// File: lib/main.dart
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
import 'dart:io';
import 'wikipedia_playback_screen.dart';

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
  final String? name;
  final String? text; // Add text field for TTS

  TourPoint({
    required this.id,
    required this.latitude,
    required this.longitude,
    required this.audioFilePath,
    this.localAudioPath,
    this.name,
    this.text,
  });

  factory TourPoint.fromJson(Map<String, dynamic> json) {
    return TourPoint(
      id: json['id'] as int,
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      audioFilePath: json['audio_filename'] as String? ?? '',
      name: json['name'] as String?,
      text: json['text'] as String?, // Parse text field
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
    var pointsList = json['waypoints'] as List<dynamic>? ?? [];
    List<TourPoint> tourPoints = pointsList.map((i) {
      try {
        return TourPoint.fromJson(i as Map<String, dynamic>);
      } catch (e) {
        print('Error parsing waypoint: $e');
        print('Waypoint data: $i');
        rethrow;
      }
    }).toList();

    return Tour(
      id: json['id'] as int,
      title: json['name'] as String? ?? 'Unnamed Tour',
      description: json['description'] as String? ?? 'No description provided',
      points: tourPoints,
    );
  }
}

class ApiService {
  // Add baseUrl as a getter to the class
  String get baseUrl {
    return serverBaseUrl.endsWith('/')
        ? serverBaseUrl.substring(0, serverBaseUrl.length - 1)
        : serverBaseUrl;
  }

  Future<List<Tour>> fetchTours() async {
    try {
      final response = await http.get(Uri.parse('$serverBaseUrl/tours/'));
      print('Response status: ${response.statusCode}');
      print('Response body: ${response.body}');

      if (response.statusCode == 200) {
        List<dynamic> toursJson = json.decode(response.body);
        return toursJson.map((json) {
          try {
            return Tour.fromJson(json as Map<String, dynamic>);
          } catch (e) {
            print('Error parsing tour: $e');
            print('Tour data: $json');
            rethrow;
          }
        }).toList();
      } else {
        throw Exception('Failed to load tours from server (Status code: ${response.statusCode})');
      }
    } catch (e) {
      print('API Error: $e');
      throw Exception('Could not connect to server or parse tours. Error: $e');
    }
  }

  Future<Tour> fetchTourDetails(int tourId) async {
    try {
      final response = await http.get(Uri.parse('$serverBaseUrl/tours/$tourId'));
      print('Tour details response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        return Tour.fromJson(json.decode(response.body) as Map<String, dynamic>);
      } else {
        throw Exception('Failed to load tour details (Status code: ${response.statusCode})');
      }
    } catch (e) {
      print('Tour details error: $e');
      throw Exception('Could not connect to server or parse tour details. Error: $e');
    }
  }

  Future<Tour> createTour(String name, String description) async {
    try {
      print('Creating tour: $name');

      // Remove trailing slash if present in base URL, then add it to the endpoint
      final url = serverBaseUrl.endsWith('/')
          ? '${serverBaseUrl}tours'
          : '$serverBaseUrl/tours';

      print('POST URL: $url');

      final response = await http.post(
        Uri.parse(url),
        headers: <String, String>{
          'Content-Type': 'application/json; charset=UTF-8',
        },
        body: jsonEncode(<String, String>{
          'name': name,
          'description': description,
        }),
      );

      print('Create tour response status: ${response.statusCode}');
      print('Create tour response body: ${response.body}');

      if (response.statusCode == 200 || response.statusCode == 201) {
        return Tour.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
      } else {
        throw Exception('Failed to create tour. Status: ${response.statusCode}, Body: ${response.body}');
      }
    } catch (e) {
      print('Error creating tour: $e');
      rethrow;
    }
  }

  Future<void> createWaypoint({
    required int tourId,
    required String name,
    required double latitude,
    required double longitude,
    required String audioFilePath,
  }) async {
    try {
      print('Creating waypoint for tour $tourId');
      print('Name: $name');
      print('Location: $latitude, $longitude');
      print('Audio file path: $audioFilePath');

      // Verify file exists before adding
      final file = File(audioFilePath);
      if (!await file.exists()) {
        throw Exception('Audio file does not exist: $audioFilePath');
      }

      final fileSize = await file.length();
      print('File exists, size: $fileSize bytes');

      final url = '$baseUrl/tours/$tourId/waypoints';

      print('POST URL: $url');

      var request = http.MultipartRequest('POST', Uri.parse(url));

      request.fields['name'] = name;
      request.fields['latitude'] = latitude.toString();
      request.fields['longitude'] = longitude.toString();

      request.files.add(
        await http.MultipartFile.fromPath('audio_file', audioFilePath),
      );

      print('Sending request to server...');
      var streamedResponse = await request.send();
      var response = await http.Response.fromStream(streamedResponse);

      print('Response status: ${response.statusCode}');
      print('Response body: ${response.body}');

      if (response.statusCode != 200 && response.statusCode != 201) {
        throw Exception(
          'Failed to upload waypoint. Status: ${response.statusCode}, Body: ${response.body}'
        );
      }

      print('Waypoint created successfully');
    } catch (e) {
      print('Error in createWaypoint: $e');
      rethrow;
    }
  }

  // New method for creating waypoint without audio (text only for TTS)
  Future<void> createWaypointWithText({
    required int tourId,
    required String name,
    required double latitude,
    required double longitude,
    required String text,
  }) async {
    try {
      print('Creating text-only waypoint for tour $tourId');
      print('Name: $name');
      print('Location: $latitude, $longitude');
      print('Text length: ${text.length} characters');

      final url = '$baseUrl/tours/$tourId/waypoints/text';

      print('POST URL: $url');

      final response = await http.post(
        Uri.parse(url),
        headers: <String, String>{
          'Content-Type': 'application/json; charset=UTF-8',
        },
        body: jsonEncode(<String, dynamic>{
          'name': name,
          'latitude': latitude,
          'longitude': longitude,
          'text': text,
        }),
      );

      print('Response status: ${response.statusCode}');
      print('Response body: ${response.body}');

      if (response.statusCode != 200 && response.statusCode != 201) {
        throw Exception(
          'Failed to create text waypoint. Status: ${response.statusCode}, Body: ${response.body}'
        );
      }

      print('Text waypoint created successfully');
    } catch (e) {
      print('Error in createWaypointWithText: $e');
      rethrow;
    }
  }

  Future<void> deleteTour(int tourId) async {
    try {
      print('Deleting tour: $tourId');

      final url = '$baseUrl/tours/$tourId';

      print('DELETE URL: $url');

      final response = await http.delete(Uri.parse(url));

      print('Delete tour response status: ${response.statusCode}');

      if (response.statusCode != 204 && response.statusCode != 200) {
        throw Exception('Failed to delete tour. Status: ${response.statusCode}');
      }

      print('Tour deleted successfully');
    } catch (e) {
      print('Error deleting tour: $e');
      rethrow;
    }
  }
}

// NOTE: The rest of the file (TourApp, ChoiceScreen, TourListScreen, etc.)
// remains unchanged from the original. Only the ApiService class has been modified.
// Add the remaining classes from your original main.dart file below this comment.

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
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Text(
                'Choose Your Experience',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: ElevatedButton.icon(
                icon: const Icon(Icons.play_arrow, size: 28),
                label: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Play Custom Tour', style: TextStyle(fontSize: 18)),
                    SizedBox(height: 4),
                    Text(
                      'Play a pre-recorded audio tour',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.normal),
                    ),
                  ],
                ),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.all(20),
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  alignment: Alignment.centerLeft,
                ),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const TourListScreen()),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: ElevatedButton.icon(
                icon: const Icon(Icons.public, size: 28),
                label: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Wikipedia Tour', style: TextStyle(fontSize: 18)),
                    SizedBox(height: 4),
                    Text(
                      'Hear about nearby places from Wikipedia',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.normal),
                    ),
                  ],
                ),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.all(20),
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                  alignment: Alignment.centerLeft,
                ),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const WikipediaPlaybackScreen(),
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: ElevatedButton.icon(
                icon: const Icon(Icons.mic, size: 28),
                label: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Record New Tour', style: TextStyle(fontSize: 18)),
                    SizedBox(height: 4),
                    Text(
                      'Create your own audio tour',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.normal),
                    ),
                  ],
                ),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.all(20),
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  alignment: Alignment.centerLeft,
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
    print('=== _finishAndSaveTour called ===');
    print('Number of waypoints: ${_newWaypoints.length}');

    if (_newWaypoints.isEmpty) {
      print('No waypoints - showing error');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please add at least one waypoint before saving the tour.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final descriptionController = TextEditingController(
      text: 'A tour recorded on ${DateFormat.yMMMd().format(DateTime.now())}'
    );

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: const Text('Add Description & Save'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Tour Name: ${widget.tourName}',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: descriptionController,
                decoration: const InputDecoration(
                  labelText: 'Tour Description',
                  hintText: 'Enter a description for your tour',
                  border: OutlineInputBorder(),
                ),
                maxLines: 3,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                print('Save dialog cancelled');
                descriptionController.dispose();
                Navigator.pop(context);
              },
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                print('Save button pressed in dialog');
                final desc = descriptionController.text.isEmpty
                    ? 'No description provided'
                    : descriptionController.text;
                print('Description: $desc');
                descriptionController.dispose();
                Navigator.pop(context);
                _uploadTour(desc);
              },
              child: const Text('Save Tour'),
            ),
          ],
        );
      },
    );
  }

  void _uploadTour(String description) async {
    print('=== _uploadTour called ===');
    print('Description: $description');
    print('Number of waypoints to upload: ${_newWaypoints.length}');

    setState(() {
      _isUploading = true;
      _uploadStatus = 'Creating tour on server...';
    });

    try {
      // Create the tour first
      print('Creating tour: ${widget.tourName}');
      final newTour = await ApiService().createTour(widget.tourName, description);
      print('✅ Tour created successfully with ID: ${newTour.id}');

      // Upload each waypoint
      for (int i = 0; i < _newWaypoints.length; i++) {
        final point = _newWaypoints[i];
        setState(() {
          _uploadStatus = 'Uploading waypoint ${i + 1} of ${_newWaypoints.length}...';
        });

        print('\n--- Uploading waypoint ${i + 1} ---');
        print('Name: ${point.name}');
        print('Lat: ${point.latitude}, Lon: ${point.longitude}');
        print('Local audio path: ${point.localAudioPath}');

        // Verify the file exists
        if (point.localAudioPath == null || point.localAudioPath!.isEmpty) {
          throw Exception('Waypoint ${i + 1} has no audio file');
        }

        final audioFile = File(point.localAudioPath!);
        if (!await audioFile.exists()) {
          throw Exception('Audio file not found for waypoint ${i + 1}: ${point.localAudioPath}');
        }

        await ApiService().createWaypoint(
          tourId: newTour.id,
          name: point.name ?? 'Waypoint ${i + 1}',
          latitude: point.latitude,
          longitude: point.longitude,
          audioFilePath: point.localAudioPath!,
        );

        print('✅ Waypoint ${i + 1} uploaded successfully');
      }

      setState(() {
        _uploadStatus = 'Upload complete!';
        _isUploading = false;
      });

      print('=== ALL UPLOADS COMPLETE ===');

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Tour saved successfully!'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 3),
        ),
      );

      // Navigate back to the main screen
      await Future.delayed(const Duration(seconds: 1));
      if (mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }

    } catch (e, stackTrace) {
      print('❌ ERROR during upload: $e');
      print('Stack trace: $stackTrace');

      setState(() {
        _uploadStatus = 'Error: ${e.toString()}';
        _isUploading = false;
      });

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Upload failed: ${e.toString()}'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  void _deleteWaypoint(int index) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Delete Waypoint'),
          content: Text('Are you sure you want to delete "${_newWaypoints[index].name}"?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _newWaypoints.removeAt(index);
                });
                Navigator.of(context).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Waypoint deleted'),
                    backgroundColor: Colors.red,
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
  }

  void _editWaypoint(int index) async {
    final editedPoint = await Navigator.push<TourPoint>(
      context,
      MaterialPageRoute(
        builder: (context) => EditWaypointScreen(
          existingWaypoint: _newWaypoints[index],
        ),
      ),
    );

    if (editedPoint != null) {
      setState(() {
        _newWaypoints[index] = editedPoint;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Waypoint "${editedPoint.name}" updated'),
          backgroundColor: Colors.blue,
        ),
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
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Text(
                      _uploadStatus,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 16),
                    ),
                  ),
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
                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.blue,
                          child: Text(
                            '${index + 1}',
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                        title: Text(point.name ?? 'Waypoint ${index + 1}'),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Lat: ${point.latitude.toStringAsFixed(4)}, Lon: ${point.longitude.toStringAsFixed(4)}'),
                            if (point.localAudioPath != null)
                              Text(
                                'Audio: ${point.localAudioPath!.split('/').last}',
                                style: const TextStyle(fontSize: 12, color: Colors.green),
                              ),
                          ],
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit, color: Colors.blue),
                              onPressed: () => _editWaypoint(index),
                              tooltip: 'Edit Waypoint',
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red),
                              onPressed: () => _deleteWaypoint(index),
                              tooltip: 'Delete Waypoint',
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
      floatingActionButton: _isUploading
          ? null
          : FloatingActionButton(
              onPressed: () async {
                final newPoint = await Navigator.push<TourPoint>(
                  context,
                  MaterialPageRoute(builder: (context) => const EditWaypointScreen()),
                );

                if (newPoint != null) {
                  setState(() {
                    _newWaypoints.add(newPoint);
                  });
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Waypoint "${newPoint.name}" added'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              },
              child: const Icon(Icons.add),
              tooltip: 'Add New Waypoint',
            ),
    );
  }
}

enum LocationMethod { gps, address, map }

class EditWaypointScreen extends StatefulWidget {
  final TourPoint? existingWaypoint;

  const EditWaypointScreen({super.key, this.existingWaypoint});

  @override
  State<EditWaypointScreen> createState() => _EditWaypointScreenState();
}

class _EditWaypointScreenState extends State<EditWaypointScreen> {
  final _nameController = TextEditingController();
  final _addressController = TextEditingController();
  final FlutterSoundRecorder _recorder = FlutterSoundRecorder();

  String _status = 'Getting location...';
  Position? _position;
  bool _isRecorderReady = false;
  bool _isRecording = false;
  String? _recordedFilePath;
  bool _isEditMode = false;
  LocationMethod _locationMethod = LocationMethod.gps;
  bool _isGeocodingAddress = false;

  @override
  void initState() {
    super.initState();
    _isEditMode = widget.existingWaypoint != null;

    if (_isEditMode) {
      _nameController.text = widget.existingWaypoint!.name ?? '';
      _position = Position(
        latitude: widget.existingWaypoint!.latitude,
        longitude: widget.existingWaypoint!.longitude,
        timestamp: DateTime.now(),
        accuracy: 0,
        altitude: 0,
        altitudeAccuracy: 0,
        heading: 0,
        headingAccuracy: 0,
        speed: 0,
        speedAccuracy: 0,
      );
      _recordedFilePath = widget.existingWaypoint!.localAudioPath;
      _status = 'Editing waypoint. You can update the name or re-record audio.';
    }

    _initialize();
  }

  Future<void> _initialize() async {
    await Permission.microphone.request();
    await Permission.location.request();

    await _recorder.openRecorder();
    setState(() => _isRecorderReady = true);

    if (!_isEditMode && _locationMethod == LocationMethod.gps) {
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
        setState(() => _status = 'Could not get location. Try using address or map instead.');
      }
    }
  }

  Future<void> _geocodeAddress() async {
    if (_addressController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter an address')),
      );
      return;
    }

    setState(() {
      _isGeocodingAddress = true;
      _status = 'Looking up address...';
    });

    try {
      List<Location> locations = await locationFromAddress(_addressController.text.trim());

      if (locations.isEmpty) {
        setState(() {
          _status = 'Address not found. Please try a different address.';
          _isGeocodingAddress = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Address not found. Please try again.'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      final location = locations.first;
      List<Placemark> placemarks = await placemarkFromCoordinates(
        location.latitude,
        location.longitude,
      );

      String formattedAddress = _addressController.text.trim();
      if (placemarks.isNotEmpty) {
        final placemark = placemarks.first;
        formattedAddress = [
          placemark.street,
          placemark.locality,
          placemark.administrativeArea,
          placemark.country,
        ].where((e) => e != null && e.isNotEmpty).join(', ');
      }

      setState(() {
        _position = Position(
          latitude: location.latitude,
          longitude: location.longitude,
          timestamp: DateTime.now(),
          accuracy: 0,
          altitude: 0,
          altitudeAccuracy: 0,
          heading: 0,
          headingAccuracy: 0,
          speed: 0,
          speedAccuracy: 0,
        );
        _nameController.text = formattedAddress;
        _status = 'Address verified! Location found.';
        _isGeocodingAddress = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Address verified: $formattedAddress'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      setState(() {
        _status = 'Error looking up address. Please try again.';
        _isGeocodingAddress = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: Could not find address. $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _openMapPicker() async {
    LatLng initialPosition = const LatLng(37.7749, -122.4194);

    try {
      Position currentPos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.low,
      );
      initialPosition = LatLng(currentPos.latitude, currentPos.longitude);
    } catch (e) {
      print('Could not get current position for map: $e');
    }

    final selectedLocation = await Navigator.push<LatLng>(
      context,
      MaterialPageRoute(
        builder: (context) => MapPickerScreen(initialPosition: initialPosition),
      ),
    );

    if (selectedLocation != null) {
      setState(() {
        _position = Position(
          latitude: selectedLocation.latitude,
          longitude: selectedLocation.longitude,
          timestamp: DateTime.now(),
          accuracy: 0,
          altitude: 0,
          altitudeAccuracy: 0,
          heading: 0,
          headingAccuracy: 0,
          speed: 0,
          speedAccuracy: 0,
        );
        _status = 'Location selected from map!';
      });

      try {
        List<Placemark> placemarks = await placemarkFromCoordinates(
          selectedLocation.latitude,
          selectedLocation.longitude,
        );
        if (placemarks.isNotEmpty) {
          final placemark = placemarks.first;
          String address = [
            placemark.street,
            placemark.locality,
            placemark.administrativeArea,
          ].where((e) => e != null && e.isNotEmpty).join(', ');

          if (address.isNotEmpty) {
            _nameController.text = address;
          } else {
            _nameController.text = "Location at ${selectedLocation.latitude.toStringAsFixed(4)}, ${selectedLocation.longitude.toStringAsFixed(4)}";
          }
        }
      } catch (e) {
        _nameController.text = "Location at ${selectedLocation.latitude.toStringAsFixed(4)}, ${selectedLocation.longitude.toStringAsFixed(4)}";
      }
    }
  }

  void _toggleRecording() async {
    if (!_isRecorderReady) return;

    if (_isRecording) {
      final path = await _recorder.stopRecorder();
      print('Recording stopped. File saved at: $path');
      setState(() {
        _recordedFilePath = path;
        _isRecording = false;
        _status = _isEditMode
            ? 'Audio re-recorded! Press Save to update.'
            : 'Audio recorded! Press Save.';
      });
    } else {
      _recordedFilePath = null;
      final filePath = 'audio_${DateTime.now().millisecondsSinceEpoch}.aac';
      print('Starting recording to: $filePath');
      await _recorder.startRecorder(toFile: filePath);
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

    print('Saving waypoint with audio file: $_recordedFilePath');

    final newPoint = TourPoint(
      id: widget.existingWaypoint?.id ?? 0,
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
    _addressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditMode ? 'Edit Waypoint' : 'Create New Waypoint'),
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
            if (!_isEditMode)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Choose location method:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            icon: Icon(_locationMethod == LocationMethod.gps ? Icons.radio_button_checked : Icons.radio_button_off),
                            label: const Text('GPS'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _locationMethod == LocationMethod.gps ? Colors.blue : Colors.grey.shade300,
                              foregroundColor: _locationMethod == LocationMethod.gps ? Colors.white : Colors.black,
                            ),
                            onPressed: () {
                              if (_locationMethod != LocationMethod.gps) {
                                setState(() {
                                  _locationMethod = LocationMethod.gps;
                                  _position = null;
                                  _addressController.clear();
                                  _status = 'Getting GPS location...';
                                });
                                _initialize();
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: ElevatedButton.icon(
                            icon: Icon(_locationMethod == LocationMethod.address ? Icons.radio_button_checked : Icons.radio_button_off),
                            label: const Text('Address'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _locationMethod == LocationMethod.address ? Colors.blue : Colors.grey.shade300,
                              foregroundColor: _locationMethod == LocationMethod.address ? Colors.white : Colors.black,
                            ),
                            onPressed: () {
                              setState(() {
                                _locationMethod = LocationMethod.address;
                                _position = null;
                                _status = 'Enter an address below';
                              });
                            },
                          ),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: ElevatedButton.icon(
                            icon: Icon(_locationMethod == LocationMethod.map ? Icons.radio_button_checked : Icons.radio_button_off),
                            label: const Text('Map'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _locationMethod == LocationMethod.map ? Colors.blue : Colors.grey.shade300,
                              foregroundColor: _locationMethod == LocationMethod.map ? Colors.white : Colors.black,
                            ),
                            onPressed: () {
                              setState(() {
                                _locationMethod = LocationMethod.map;
                                _position = null;
                                _status = 'Tap button below to select location on map';
                              });
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 16),

            if (_locationMethod == LocationMethod.address && !_isEditMode)
              Column(
                children: [
                  TextField(
                    controller: _addressController,
                    decoration: const InputDecoration(
                      labelText: 'Enter Address',
                      hintText: 'e.g., 1600 Amphitheatre Parkway, Mountain View, CA',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.location_on),
                    ),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    icon: _isGeocodingAddress
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.search),
                    label: Text(_isGeocodingAddress ? 'Verifying...' : 'Verify Address'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: _isGeocodingAddress ? null : _geocodeAddress,
                  ),
                  const SizedBox(height: 16),
                ],
              ),

            if (_locationMethod == LocationMethod.map && !_isEditMode)
              Column(
                children: [
                  ElevatedButton.icon(
                    icon: const Icon(Icons.map),
                    label: Text(_position == null ? 'Select Location on Map' : 'Change Location on Map'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                    ),
                    onPressed: _openMapPicker,
                  ),
                  const SizedBox(height: 16),
                ],
              ),

            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _position != null ? Colors.green.shade50 : Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _position != null ? Colors.green : Colors.orange,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _position != null ? Icons.check_circle : Icons.info_outline,
                    color: _position != null ? Colors.green : Colors.orange,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(_status, style: const TextStyle(fontSize: 14)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            if (_position != null)
              Text(
                'Lat: ${_position!.latitude.toStringAsFixed(4)}, Lon: ${_position!.longitude.toStringAsFixed(4)}',
                style: const TextStyle(color: Colors.grey),
              ),
            const SizedBox(height: 20),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Waypoint Name',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.label),
              ),
            ),
            const SizedBox(height: 30),
            ElevatedButton.icon(
              icon: Icon(_isRecording ? Icons.stop : Icons.mic),
              label: Text(_isRecording ? 'Stop Recording' : (_isEditMode && _recordedFilePath != null ? 'Re-record Audio' : 'Record Audio')),
              style: ElevatedButton.styleFrom(
                backgroundColor: _isRecording ? Colors.red : Colors.green,
                padding: const EdgeInsets.symmetric(vertical: 15),
              ),
              onPressed: _isRecorderReady && _position != null ? _toggleRecording : null,
            ),
            if (_recordedFilePath != null && !_isRecording)
              Padding(
                padding: const EdgeInsets.only(top: 10.0),
                child: Column(
                  children: [
                    Icon(Icons.check_circle, color: Colors.green[700], size: 32),
                    const SizedBox(height: 8),
                    Text(
                      'Audio saved: ${_recordedFilePath!.split('/').last}',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.green[700], fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            if (_isEditMode)
              Padding(
                padding: const EdgeInsets.only(top: 20.0),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline, color: Colors.blue),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Edit mode: Location is locked. You can update the name and re-record audio.',
                          style: TextStyle(color: Colors.blue[900], fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}


class MapPickerScreen extends StatefulWidget {
  final LatLng initialPosition;

  const MapPickerScreen({super.key, required this.initialPosition});

  @override
  State<MapPickerScreen> createState() => _MapPickerScreenState();
}

class _MapPickerScreenState extends State<MapPickerScreen> {
  late LatLng _selectedPosition;
  final Completer<GoogleMapController> _mapController = Completer();
  Set<Marker> _markers = {};
  String _addressPreview = 'Tap on the map to select a location';

  @override
  void initState() {
    super.initState();
    _selectedPosition = widget.initialPosition;
    _addMarker(_selectedPosition);
    _getAddressFromLatLng(_selectedPosition);
  }

  void _addMarker(LatLng position) {
    setState(() {
      _markers = {
        Marker(
          markerId: const MarkerId('selected_location'),
          position: position,
          draggable: true,
          onDragEnd: (newPosition) {
            _onMapTapped(newPosition);
          },
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
        ),
      };
    });
  }

  void _onMapTapped(LatLng position) {
    setState(() {
      _selectedPosition = position;
      _addMarker(position);
    });
    _getAddressFromLatLng(position);
  }

  Future<void> _getAddressFromLatLng(LatLng position) async {
    try {
      List<Placemark> placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );

      if (placemarks.isNotEmpty) {
        final placemark = placemarks.first;
        String address = [
          placemark.street,
          placemark.locality,
          placemark.administrativeArea,
          placemark.country,
        ].where((e) => e != null && e.isNotEmpty).join(', ');

        setState(() {
          _addressPreview = address.isNotEmpty
              ? address
              : '${position.latitude.toStringAsFixed(4)}, ${position.longitude.toStringAsFixed(4)}';
        });
      } else {
        setState(() {
          _addressPreview = '${position.latitude.toStringAsFixed(4)}, ${position.longitude.toStringAsFixed(4)}';
        });
      }
    } catch (e) {
      setState(() {
        _addressPreview = '${position.latitude.toStringAsFixed(4)}, ${position.longitude.toStringAsFixed(4)}';
      });
    }
  }

  void _confirmSelection() {
    Navigator.pop(context, _selectedPosition);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Select Location'),
        actions: [
          IconButton(
            icon: const Icon(Icons.check),
            onPressed: _confirmSelection,
            tooltip: 'Confirm Location',
          ),
        ],
      ),
      body: Stack(
        children: [
          GoogleMap(
            onMapCreated: (controller) => _mapController.complete(controller),
            initialCameraPosition: CameraPosition(
              target: widget.initialPosition,
              zoom: 15.0,
            ),
            markers: _markers,
            onTap: _onMapTapped,
            myLocationEnabled: true,
            myLocationButtonEnabled: true,
            mapType: MapType.normal,
            zoomControlsEnabled: true,
          ),
          Positioned(
            top: 16,
            left: 16,
            right: 16,
            child: Card(
              elevation: 8,
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: const [
                        Icon(Icons.info_outline, color: Colors.blue),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Tap anywhere on the map to select a location',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'You can also drag the marker to adjust',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 16,
            left: 16,
            right: 16,
            child: Card(
              elevation: 8,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Selected Location:',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _addressPreview,
                      style: const TextStyle(fontSize: 14),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Lat: ${_selectedPosition.latitude.toStringAsFixed(6)}, Lon: ${_selectedPosition.longitude.toStringAsFixed(6)}',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.check_circle),
                        label: const Text('Confirm This Location'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        onPressed: _confirmSelection,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
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

  void _refreshTours() {
    setState(() {
      futureTours = ApiService().fetchTours();
    });
  }

  Future<void> _deleteTour(Tour tour) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Delete Tour'),
          content: Text('Are you sure you want to delete "${tour.title}"? This action cannot be undone.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Deleting tour...'),
        duration: Duration(seconds: 1),
      ),
    );

    try {
      await ApiService().deleteTour(tour.id);
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Tour "${tour.title}" deleted successfully'),
          backgroundColor: Colors.green,
        ),
      );

      _refreshTours();
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to delete tour: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Select a Tour'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refreshTours,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: FutureBuilder<List<Tour>>(
        future: futureTours,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          } else if (snapshot.hasError) {
            return Center(child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 48, color: Colors.red),
                  const SizedBox(height: 16),
                  Text('Error: ${snapshot.error}', textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry'),
                    onPressed: _refreshTours,
                  ),
                ],
              ),
            ));
          } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.tour, size: 64, color: Colors.grey),
                  const SizedBox(height: 16),
                  const Text('No tours found on the server.', style: TextStyle(fontSize: 16)),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    icon: const Icon(Icons.refresh),
                    label: const Text('Refresh'),
                    onPressed: _refreshTours,
                  ),
                ],
              ),
            );
          } else {
            List<Tour> tours = snapshot.data!;
            return ListView.builder(
              itemCount: tours.length,
              itemBuilder: (context, index) {
                final tour = tours[index];
                return Dismissible(
                  key: Key(tour.id.toString()),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    color: Colors.red,
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 20.0),
                    child: const Icon(Icons.delete, color: Colors.white, size: 32),
                  ),
                  confirmDismiss: (direction) async {
                    return await showDialog<bool>(
                      context: context,
                      builder: (BuildContext context) {
                        return AlertDialog(
                          title: const Text('Delete Tour'),
                          content: Text('Are you sure you want to delete "${tour.title}"?'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.of(context).pop(false),
                              child: const Text('Cancel'),
                            ),
                            ElevatedButton(
                              onPressed: () => Navigator.of(context).pop(true),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red,
                                foregroundColor: Colors.white,
                              ),
                              child: const Text('Delete'),
                            ),
                          ],
                        );
                      },
                    );
                  },
                  onDismissed: (direction) async {
                    try {
                      await ApiService().deleteTour(tour.id);
                      if (!mounted) return;

                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Tour "${tour.title}" deleted'),
                          backgroundColor: Colors.green,
                        ),
                      );

                      _refreshTours();
                    } catch (e) {
                      if (!mounted) return;

                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Failed to delete: $e'),
                          backgroundColor: Colors.red,
                        ),
                      );

                      _refreshTours();
                    }
                  },
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Colors.blue,
                      child: Text('${tour.points.length}', style: const TextStyle(color: Colors.white)),
                    ),
                    title: Text(tour.title),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(tour.description),
                        const SizedBox(height: 4),
                        Text(
                          '${tour.points.length} waypoint${tour.points.length != 1 ? 's' : ''}',
                          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                        ),
                      ],
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                      onPressed: () => _deleteTour(tour),
                      tooltip: 'Delete Tour',
                    ),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => TourPlaybackScreen(tourId: tour.id),
                        ),
                      );
                    },
                  ),
                );
              },
            );
          }
        },
      ),
    );
  }
}

enum PlaybackMode {
  sequential, // Play in insertion order
  proximity,  // Play when approaching (current behavior)
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

  // New state variables for playback modes
  PlaybackMode _playbackMode = PlaybackMode.sequential;
  Set<int> _completedWaypoints = {};
  bool _tourStarted = false;

  @override
  void initState() {
    super.initState();
    _loadTourDetails();
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

  // Handle audio completion - marks waypoint as completed
  void _handleAudioCompleted() {
    setState(() {
      _isAudioPlaying = false;
      _completedWaypoints.add(_currentPointIndex);

      if (_playbackMode == PlaybackMode.sequential) {
        // In sequential mode, automatically move to next waypoint
        _moveToNextWaypoint();
      } else {
        // In proximity mode, wait for user to approach next waypoint
        _statusMessage = "Waypoint completed! Approach another waypoint to continue.";
        _updateMarkers();
      }
    });
  }

  // Skip button handler - marks current waypoint as completed
  void _skipCurrentWaypoint() {
    if (_isAudioPlaying) {
      _audioPlayer.stop();
    }

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Skip Waypoint'),
          content: Text(
            'Skip waypoint ${_currentPointIndex + 1}?',
          ),
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
                    _statusMessage = "Waypoint skipped. Approach another waypoint.";
                    _updateMarkers();
                  });
                }

                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Skipped waypoint ${_currentPointIndex + 1}'),
                    backgroundColor: Colors.orange,
                  ),
                );
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

  // Move to next waypoint (Sequential mode)
  void _moveToNextWaypoint() {
    if (_tour == null) return;

    setState(() {
      _isAudioPlaying = false;
      _currentPointIndex++;

      if (_currentPointIndex >= _tour!.points.length) {
        _statusMessage = "Tour completed! All ${_tour!.points.length} waypoints visited.";
        _positionStreamSubscription?.cancel();
        _updateMarkers();
      } else {
        _statusMessage = "Moving to waypoint ${_currentPointIndex + 1}/${_tour!.points.length}";
        _goToPoint(_tour!.points[_currentPointIndex]);
        _updateMarkers();
      }
    });
  }

  // Start the tour based on selected mode
  void _startTour() {
    setState(() {
      _tourStarted = true;
      _completedWaypoints.clear();
      _currentPointIndex = 0;
    });

    if (_playbackMode == PlaybackMode.sequential) {
      _startSequentialMode();
    } else {
      _startProximityMode();
    }
  }

  // Sequential Mode: Play waypoints in insertion order
  void _startSequentialMode() {
    if (_tour == null || _tour!.points.isEmpty) return;

    setState(() {
      _statusMessage = "Sequential Mode: Approach waypoint 1/${_tour!.points.length}";
    });

    _goToPoint(_tour!.points[0]);
    _updateMarkers();
    _startLocationListener();
  }

  // Proximity Mode: Play any waypoint when approaching
  void _startProximityMode() {
    setState(() {
      _statusMessage = "Proximity Mode: Approach any waypoint to start";
    });

    _updateMarkers();
    _startLocationListener();
  }

  Future<void> _startLocationListener() async {
    await _determinePosition();
    _positionStreamSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
      ),
    ).listen((Position position) {
      if (!mounted || _tour == null || !_tourStarted) {
        return;
      }

      if (_playbackMode == PlaybackMode.sequential) {
        _handleSequentialLocationUpdate(position);
      } else {
        _handleProximityLocationUpdate(position);
      }
    });
  }

  // Handle location updates in Sequential mode
  void _handleSequentialLocationUpdate(Position position) {
    if (_currentPointIndex >= _tour!.points.length || _isAudioPlaying) {
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
        _statusMessage = "Waypoint ${_currentPointIndex + 1}/${_tour!.points.length}: ${distanceInMeters.toStringAsFixed(0)}m away";
      }
    });

    // Trigger audio when within 25 meters
    if (distanceInMeters < 25 && !_completedWaypoints.contains(_currentPointIndex)) {
      _playAudioForPoint(currentTargetPoint, _currentPointIndex);
    }
  }

  // Handle location updates in Proximity mode
  void _handleProximityLocationUpdate(Position position) {
    if (_isAudioPlaying || _tour == null) {
      return;
    }

    // Find the nearest unplayed waypoint
    int? nearestIndex;
    double nearestDistance = double.infinity;

    for (int i = 0; i < _tour!.points.length; i++) {
      if (_completedWaypoints.contains(i)) continue;

      final point = _tour!.points[i];
      final distance = Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        point.latitude,
        point.longitude,
      );

      if (distance < nearestDistance) {
        nearestDistance = distance;
        nearestIndex = i;
      }
    }

    if (nearestIndex != null) {
      final point = _tour!.points[nearestIndex];
      final waypointNumber = nearestIndex + 1;
      setState(() {
        _statusMessage = "Nearest: Waypoint $waypointNumber (${nearestDistance.toStringAsFixed(0)}m) - ${_completedWaypoints.length}/${_tour!.points.length} completed";
      });

      // Trigger audio when within 25 meters
      if (nearestDistance < 25) {
        _currentPointIndex = nearestIndex;
        _playAudioForPoint(point, nearestIndex);
      }
    } else {
      setState(() {
        _statusMessage = "All waypoints completed! ${_completedWaypoints.length}/${_tour!.points.length}";
      });
    }
  }

  Future<void> _playAudioForPoint(TourPoint point, int index) async {
    setState(() {
      _isAudioPlaying = true;
      _currentPointIndex = index;
      _statusMessage = "Playing audio for waypoint ${index + 1}/${_tour!.points.length}";
    });

    try {
      final audioUrl = '$serverBaseUrl/uploads/${point.audioFilePath}';
      print('Playing audio from: $audioUrl');

      await _audioPlayer.setUrl(audioUrl);
      _audioPlayer.play();
      _updateMarkers();
    } catch (e) {
      print('Error playing audio: $e');
      if (!mounted) return;
      setState(() {
        _statusMessage = "Error playing audio: $e";
        _isAudioPlaying = false;
      });
    }
  }

  void _updateMarkers() {
    if (_tour == null) return;

    setState(() {
      _markers = _tour!.points.asMap().entries.map((entry) {
        int index = entry.key;
        TourPoint p = entry.value;

        // Determine marker color based on state
        BitmapDescriptor markerColor;
        if (_completedWaypoints.contains(index)) {
          // Completed: Purple
          markerColor = BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueViolet);
        } else if (index == _currentPointIndex && _tourStarted) {
          // Current: Green
          markerColor = BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen);
        } else {
          // Unvisited: Red
          markerColor = BitmapDescriptor.defaultMarker;
        }

        return Marker(
          markerId: MarkerId(p.id.toString()),
          position: LatLng(p.latitude, p.longitude),
          infoWindow: InfoWindow(
            title: '${index + 1}. ${p.name ?? 'Point ${p.id}'}',
            snippet: _completedWaypoints.contains(index) ? 'Completed ✓' : null,
          ),
          icon: markerColor,
        );
      }).toSet();
    });
  }

  Future<void> _loadTourDetails() async {
    try {
      final tour = await ApiService().fetchTourDetails(widget.tourId);
      if (!mounted) return;
      setState(() {
        _tour = tour;
        _statusMessage = 'Tour loaded. Select a playback mode to begin.';
        _updateMarkers();
      });
      if (tour.points.isNotEmpty) {
        _goToPoint(tour.points.first);
      }
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
      ),
    ));
  }

  Future<void> _determinePosition() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      setState(() {
        _statusMessage = 'Location services are disabled.';
      });
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        setState(() {
          _statusMessage = 'Location permissions are denied';
        });
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      setState(() {
        _statusMessage = 'Location permissions are permanently denied';
      });
      return;
    }

    // Actually get the current position
    try {
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      print('Current position obtained: ${position.latitude}, ${position.longitude}');
      setState(() {
        _statusMessage = 'Location found! Ready to start tour.';
      });
    } catch (e) {
      print('Error getting current position: $e');
      setState(() {
        _statusMessage = 'Error getting location: $e';
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
        title: Text(_tour?.title ?? 'Tour Playback'),
        backgroundColor: Colors.blue,
      ),
      body: Column(
        children: [
          // Mode Selection Panel (only show before tour starts)
          if (!_tourStarted && _tour != null)
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
                            padding: const EdgeInsets.symmetric(vertical: 12),
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
                                ? Colors.green
                                : Colors.grey.shade300,
                            foregroundColor: _playbackMode == PlaybackMode.proximity
                                ? Colors.white
                                : Colors.black,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _playbackMode == PlaybackMode.sequential
                        ? '📍 Follow waypoints in order (1→2→3...)'
                        : '🧭 Explore freely - play waypoints as you approach them',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
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
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // Status Bar
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
                  child: Text(
                    _statusMessage,
                    style: const TextStyle(fontSize: 14),
                  ),
                ),
                if (_tourStarted)
                  Chip(
                    label: Text(
                      '${_completedWaypoints.length}/${_tour?.points.length ?? 0}',
                      style: const TextStyle(fontSize: 12),
                    ),
                    backgroundColor: Colors.blue.shade100,
                  ),
              ],
            ),
          ),

          // Map
          Expanded(
            child: _tour == null
                ? const Center(child: CircularProgressIndicator())
                : GoogleMap(
                    initialCameraPosition: CameraPosition(
                      target: _tour!.points.isNotEmpty
                          ? LatLng(_tour!.points.first.latitude, _tour!.points.first.longitude)
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

          // Control Buttons
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
                      onPressed: _isAudioPlaying || _currentPointIndex >= (_tour?.points.length ?? 0)
                          ? _skipCurrentWaypoint
                          : null,
                      icon: const Icon(Icons.skip_next),
                      label: const Text('Skip Waypoint'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        disabledBackgroundColor: Colors.grey.shade300,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        showDialog(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('Legend'),
                            content: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildLegendItem(Colors.red, 'Unvisited waypoint'),
                                _buildLegendItem(Colors.green, 'Current waypoint'),
                                _buildLegendItem(Colors.purple, 'Completed waypoint'),
                              ],
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: const Text('Close'),
                              ),
                            ],
                          ),
                        );
                      },
                      icon: const Icon(Icons.info_outline),
                      label: const Text('Legend'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
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

  Widget _buildLegendItem(Color color, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(text),
        ],
      ),
    );
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
