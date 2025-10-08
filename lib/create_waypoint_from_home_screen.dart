// File: lib/create_waypoint_from_home_screen.dart

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:file_picker/file_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';

const String baseUrl = "https://tour-app-server.onrender.com";

class CreateWaypointFromHomeScreen extends StatefulWidget {
  const CreateWaypointFromHomeScreen({super.key});

  @override
  State<CreateWaypointFromHomeScreen> createState() => _CreateWaypointFromHomeScreenState();
}

class _CreateWaypointFromHomeScreenState extends State<CreateWaypointFromHomeScreen> {
  final _nameController = TextEditingController();
  File? _audioFile;
  bool _isUploading = false;
  String _statusMessage = 'Getting location...';
  Position? _currentPosition;

  @override
  void initState() {
    super.initState();
    _getCurrentLocation();
  }

  Future<void> _getCurrentLocation() async {
    try {
      // Check if location services are enabled
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() {
          _statusMessage = 'Location services are disabled. Please enable them.';
        });
        return;
      }

      // Check location permissions
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          setState(() {
            _statusMessage = 'Location permissions are denied.';
          });
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        setState(() {
          _statusMessage = 'Location permissions are permanently denied.';
        });
        return;
      }

      // Get current position
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      // Try to get address from coordinates
      try {
        List<Placemark> placemarks = await placemarkFromCoordinates(
          position.latitude,
          position.longitude,
        );

        if (placemarks.isNotEmpty) {
          final placemark = placemarks.first;
          String address = '';
          if (placemark.street != null && placemark.street!.isNotEmpty) {
            address = placemark.street!;
          }
          if (placemark.locality != null && placemark.locality!.isNotEmpty) {
            if (address.isNotEmpty) address += ', ';
            address += placemark.locality!;
          }
          _nameController.text = address.isNotEmpty ? address : 'Home';
        } else {
          _nameController.text = 'Home';
        }
      } catch (e) {
        _nameController.text = 'Home';
      }

      setState(() {
        _currentPosition = position;
        _statusMessage = 'Location found: ${position.latitude.toStringAsFixed(4)}, ${position.longitude.toStringAsFixed(4)}';
      });
    } catch (e) {
      setState(() {
        _statusMessage = 'Error getting location: $e';
      });
    }
  }

  String _getFileName(String filePath) {
    return filePath.split('/').last;
  }

  Future<void> _pickAudioFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['aac', 'mp3', 'm4a'],
    );

    if (result != null) {
      setState(() {
        _audioFile = File(result.files.single.path!);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Selected file: ${_getFileName(_audioFile!.path)}')),
      );
    }
  }

  Future<void> _submitWaypoint() async {
    if (_audioFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select an audio file.')),
      );
      return;
    }

    if (_currentPosition == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Location not available. Please wait or try again.')),
      );
      return;
    }

    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a waypoint name.')),
      );
      return;
    }

    const int tourId = 1;

    setState(() {
      _isUploading = true;
    });

    try {
      final url = Uri.parse('$baseUrl/tours/$tourId/waypoints');
      var request = http.MultipartRequest('POST', url);

      request.files.add(await http.MultipartFile.fromPath(
        'audio_file',
        _audioFile!.path,
        filename: _getFileName(_audioFile!.path),
      ));

      request.fields['name'] = _nameController.text.trim();
      request.fields['latitude'] = _currentPosition!.latitude.toString();
      request.fields['longitude'] = _currentPosition!.longitude.toString();

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
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create New Waypoint'),
        backgroundColor: Colors.blueAccent,
        foregroundColor: Colors.white,
      ),
      body: _isUploading
          ? const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Colors.blueAccent),
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _currentPosition != null
                          ? Colors.green.shade50
                          : Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: _currentPosition != null
                            ? Colors.green
                            : Colors.orange,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _currentPosition != null
                              ? Icons.check_circle
                              : Icons.location_searching,
                          color: _currentPosition != null
                              ? Colors.green
                              : Colors.orange,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _statusMessage,
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                        if (_currentPosition == null)
                          IconButton(
                            icon: const Icon(Icons.refresh),
                            onPressed: _getCurrentLocation,
                            tooltip: 'Retry',
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: 'Waypoint Name',
                      border: OutlineInputBorder(),
                      hintText: 'e.g., Home, My Place',
                      prefixIcon: Icon(Icons.label),
                    ),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton.icon(
                    icon: Icon(_audioFile == null ? Icons.file_upload : Icons.check),
                    label: Text(
                      _audioFile == null
                          ? 'Select Audio File'
                          : 'File: ${_getFileName(_audioFile!.path)}',
                    ),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      backgroundColor: _audioFile == null
                          ? Colors.grey.shade300
                          : Colors.green.shade100,
                    ),
                    onPressed: _pickAudioFile,
                  ),
                  const SizedBox(height: 30),
                  ElevatedButton(
                    onPressed: _currentPosition != null && _audioFile != null
                        ? _submitWaypoint
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blueAccent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      disabledBackgroundColor: Colors.grey.shade300,
                    ),
                    child: const Text(
                      'Add Waypoint',
                      style: TextStyle(fontSize: 18),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
