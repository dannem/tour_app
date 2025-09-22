// File: lib/create_waypoint_from_home_screen.dart

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as path; // Add 'as path' to create an alias

const String baseUrl = "https://tour-app-server.onrender.com";

class CreateWaypointFromHomeScreen extends StatefulWidget {
  const CreateWaypointFromHomeScreen({super.key});

  @override
  State<CreateWaypointFromHomeScreen> createState() => _CreateWaypointFromHomeScreenState();
}

class _CreateWaypointFromHomeScreenState extends State<CreateWaypointFromHomeScreen> {
  final _addressController = TextEditingController();
  final _latController = TextEditingController();
  final _lonController = TextEditingController();
  File? _audioFile;
  bool _isUploading = false;

  Future<void> _pickAudioFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['aac', 'mp3', 'm4a'],
    );

    if (result != null) {
      setState(() {
        _audioFile = File(result.files.single.path!);
      });
      // Use path.basename to avoid conflict
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Selected file: ${path.basename(_audioFile!.path)}')),
      );
    }
  }

  Future<void> _submitWaypoint() async {
    final address = _addressController.text.trim();
    final latitude = double.tryParse(_latController.text.trim());
    final longitude = double.tryParse(_lonController.text.trim());

    if (_audioFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select an audio file.')),
      );
      return;
    }

    if (address.isEmpty && (latitude == null || longitude == null)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter an address or coordinates.')),
      );
      return;
    }

    const int tourId = 1;

    setState(() {
      _isUploading = true;
    });

    try {
      final url = Uri.parse('$baseUrl/tours/$tourId/waypoints/from_home');
      var request = http.MultipartRequest('POST', url);

      request.files.add(await http.MultipartFile.fromPath(
        'audio_file',
        _audioFile!.path,
        filename: path.basename(_audioFile!.path), // Use path.basename
      ));

      if (address.isNotEmpty) {
        request.fields['address'] = address;
      } else {
        request.fields['latitude'] = latitude!.toString();
        request.fields['longitude'] = longitude!.toString();
      }

      final response = await request.send();

      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Waypoint added successfully!')),
        );
        Navigator.of(context).pop();
      } else {
        final responseBody = await response.stream.bytesToString();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to add waypoint: $responseBody')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('An error occurred: $e')),
      );
    } finally {
      setState(() {
        _isUploading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Add Waypoint From Home'),
        backgroundColor: Colors.blueAccent,
        foregroundColor: Colors.white,
      ),
      body: _isUploading
          ? const Center(child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(Colors.blueAccent)))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  TextField(
                    controller: _addressController,
                    decoration: const InputDecoration(
                      labelText: 'Address',
                      border: OutlineInputBorder(),
                      hintText: 'e.g., Eiffel Tower, Paris',
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Center(child: Text('OR', style: TextStyle(fontWeight: FontWeight.bold))),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _latController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Latitude',
                      border: OutlineInputBorder(),
                      hintText: 'e.g., 48.8584',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _lonController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Longitude',
                      border: OutlineInputBorder(),
                      hintText: 'e.g., 2.2945',
                    ),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.file_upload),
                    label: Text(_audioFile == null ? 'Select Audio File' : 'File Selected: ${path.basename(_audioFile!.path)}'),
                    onPressed: _pickAudioFile,
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: _submitWaypoint,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blueAccent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                    ),
                    child: const Text('Add Waypoint', style: TextStyle(fontSize: 18)),
                  ),
                ],
              ),
            ),
    );
  }
}
