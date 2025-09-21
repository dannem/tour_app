import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:permission_handler/permission_handler.dart';

// Ensure the server URL is correct.
// If you've deployed your server on Render, replace this with your public URL.
const String baseUrl = "https://tour-app-server.onrender.com";

void main() {
  runApp(const TourApp());
}

class TourApp extends StatelessWidget {
  const TourApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Tour App',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const TourCreationScreen(),
    );
  }
}

class TourCreationScreen extends StatefulWidget {
  const TourCreationScreen({super.key});

  @override
  _TourCreationScreenState createState() => _TourCreationScreenState();
}

class _TourCreationScreenState extends State<TourCreationScreen> {
  final TextEditingController _tourNameController = TextEditingController();
  final TextEditingController _tourDescriptionController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _audioPathController = TextEditingController();

  final FlutterSoundRecorder _recorder = FlutterSoundRecorder();
  String? _recordingPath;
  bool _isRecording = false;

  @override
  void initState() {
    super.initState();
    _openRecorder();
  }

  Future<void> _openRecorder() async {
    final status = await Permission.microphone.request();
    if (status != PermissionStatus.granted) {
      throw RecordingPermissionException('Microphone permission not granted');
    }
    await _recorder.openRecorder();
  }

  Future<void> _startRecording() async {
    if (_isRecording) return;
    try {
      final String path = await _recorder.startRecorder(
        toFile: 'waypoint_audio.aac',
        codec: Codec.aacADTS,
      ) as String;
      setState(() {
        _recordingPath = path;
        _isRecording = true;
      });
    } catch (e) {
      print('Error starting recording: $e');
    }
  }

  Future<void> _stopRecording() async {
    if (!_isRecording) return;
    await _recorder.stopRecorder();
    setState(() {
      _isRecording = false;
    });
  }

  Future<void> _createTour() async {
    final String name = _tourNameController.text;
    final String description = _tourDescriptionController.text;

    try {
      final response = await http.post(
        Uri.parse('$serverUrl/tours/'),
        headers: <String, String>{
          'Content-Type': 'application/json; charset=UTF-8',
        },
        body: jsonEncode({
          'name': name,
          'description': description,
        }),
      );

      if (response.statusCode == 200) {
        final tourData = jsonDecode(response.body);
        final tourId = tourData['id'];
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Tour "$name" created successfully! ID: $tourId')));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to create tour: ${response.body}')));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _addWaypointFromAddress() async {
    final String tourId = _tourNameController.text; // Assuming tour name is unique and can be used as ID for simplicity
    final String address = _addressController.text;
    final String audioFilePath = _recordingPath ?? '';
    if (tourId.isEmpty || address.isEmpty || audioFilePath.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please fill all fields and record audio.')));
      return;
    }

    try {
      final file = File(audioFilePath);
      final bytes = await file.readAsBytes();

      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$serverUrl/tours/$tourId/waypoints-from-home'),
      )
        ..fields['address'] = address
        ..files.add(http.MultipartFile.fromBytes(
          'audio_file',
          bytes,
          filename: 'audio.aac',
        ));

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Waypoint from address added successfully!')));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to add waypoint: ${response.body}')));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  @override
  void dispose() {
    _recorder.closeRecorder();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Tour'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            TextField(
              controller: _tourNameController,
              decoration: const InputDecoration(
                labelText: 'Tour Name',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _tourDescriptionController,
              decoration: const InputDecoration(
                labelText: 'Tour Description',
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _createTour,
              child: const Text('Create New Tour'),
            ),
            const SizedBox(height: 40),
            const Text('Add Waypoint from Address', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            TextField(
              controller: _addressController,
              decoration: const InputDecoration(
                labelText: 'Address',
              ),
            ),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: _isRecording ? _stopRecording : _startRecording,
              style: ElevatedButton.styleFrom(
                backgroundColor: _isRecording ? Colors.red : Colors.green,
              ),
              child: Text(_isRecording ? 'Stop Recording' : 'Start Recording'),
            ),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: _addWaypointFromAddress,
              child: const Text('Add Waypoint'),
            ),
          ],
        ),
      ),
    );
  }
}
