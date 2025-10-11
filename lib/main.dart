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
      id: json['id'] as int,
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      audioFilePath: json['audio_filename'] as String? ?? '',
      name: json['name'] as String?,
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
      description: json['description'] as String? ?? '',
      points: tourPoints,
    );
  }
}

class ApiService {
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

      // Remove trailing slash if present, construct proper URL
      final baseUrl = serverBaseUrl.endsWith('/')
          ? serverBaseUrl.substring(0, serverBaseUrl.length - 1)
          : serverBaseUrl;
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
  Future<void> deleteTour(int tourId) async {
    try {
      print('Deleting tour: $tourId');

      final baseUrl = serverBaseUrl.endsWith('/')
          ? serverBaseUrl.substring(0, serverBaseUrl.length - 1)
          : serverBaseUrl;
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
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Manual Recording not implemented yet.'))
                  );
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
class EditWaypointScreen extends StatefulWidget {
  final TourPoint? existingWaypoint;

  const EditWaypointScreen({super.key, this.existingWaypoint});

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
  bool _isEditMode = false;

  @override
  void initState() {
    super.initState();
    _isEditMode = widget.existingWaypoint != null;

    if (_isEditMode) {
      // Populate fields with existing waypoint data
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

    // Only get new location if this is a new waypoint
    if (!_isEditMode) {
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
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _position != null ? Colors.green.shade50 : Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _position != null ? Colors.green : Colors.orange,
                ),
              ),
              child: Text(_status, style: const TextStyle(fontSize: 14)),
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
            infoWindow: InfoWindow(title: point.name ?? 'Point ${point.id}'),
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
      // Construct the correct audio URL - the audioFilePath is just the filename
      final audioUrl = '$serverBaseUrl/uploads/${point.audioFilePath}';
      print('Playing audio from: $audioUrl');

      await _audioPlayer.setUrl(audioUrl);
      _audioPlayer.play();
    } catch (e) {
      print('Error playing audio: $e');
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
