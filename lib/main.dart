import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'dart:convert';
import 'dart:async';

// --- IMPORTANT ---
// This is now pointing to your live Render server.
const String serverBaseUrl = "https://tour-app-server.onrender.com";
// ---------------

void main() {
  runApp(const TourApp());
}

//-------------------------------------------------
// Data Models (FIXED to match your server's JSON)
//-------------------------------------------------
class TourPoint {
  final int id;
  // final String title; // REMOVED - Server doesn't provide a title for each point
  final double latitude;
  final double longitude;
  final String audioFilePath;

  TourPoint({
    required this.id,
    required this.latitude,
    required this.longitude,
    required this.audioFilePath,
  });

  // UPDATED FACTORY
  factory TourPoint.fromJson(Map<String, dynamic> json) {
    return TourPoint(
      id: json['id'],
      latitude: json['latitude'],
      longitude: json['longitude'],
      // Corrected field name to match server JSON
      audioFilePath: json['audio_filename'],
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

  // UPDATED FACTORY
  factory Tour.fromJson(Map<String, dynamic> json) {
    // Corrected field name to match server JSON
    var pointsList = json['waypoints'] as List? ?? [];
    List<TourPoint> tourPoints = pointsList.map((i) => TourPoint.fromJson(i)).toList();
    return Tour(
      id: json['id'],
      // Corrected field name to match server JSON
      title: json['name'],
      description: json['description'],
      points: tourPoints,
    );
  }
}


//-------------------------------------------------
// API Service (to talk to the server)
//-------------------------------------------------
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
      throw Exception('Could not connect to server or parse tours. Is your Python server running? Error: $e');
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
}


//-------------------------------------------------
// Main App Widget
//-------------------------------------------------
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

//-------------------------------------------------
// 1. The Home Screen with Three Choices
//-------------------------------------------------
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
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const MapScreen()),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: ElevatedButton.icon(
                icon: const Icon(Icons.location_on),
                label: const Text('Record at Location'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  textStyle: const TextStyle(fontSize: 18),
                ),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const LocationRecordingScreen()),
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

//-------------------------------------------------
// 2. Screen to List Tours from Server
//-------------------------------------------------
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


//-------------------------------------------------
// 3. Screen for Tour Playback
//-------------------------------------------------
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

  Tour? _tour;
  Set<Marker> _markers = {};
  int _currentPointIndex = 0;
  String _statusMessage = 'Loading tour...';
  bool _hasPlayedCurrent = false;

  @override
  void initState() {
    super.initState();
    _loadTourDetails();
  }

  Future<void> _loadTourDetails() async {
    try {
      final tour = await ApiService().fetchTourDetails(widget.tourId);
      setState(() {
        _tour = tour;
        _statusMessage = 'Tour loaded. Waiting for location...';
        _markers = tour.points.map((point) {
          return Marker(
            markerId: MarkerId(point.id.toString()),
            position: LatLng(point.latitude, point.longitude),
            // UPDATED - Use point ID since there's no title
            infoWindow: InfoWindow(title: 'Point ${point.id}'),
          );
        }).toSet();
      });
       if (tour.points.isNotEmpty) {
        // Move camera to the first point of the tour
        _goToPoint(tour.points.first);
      }
      _startLocationListener();
    } catch (e) {
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
    // First, get permissions
     await _determinePosition();
    // Then start listening
    _positionStreamSubscription = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 10)
    ).listen((Position position) {
      if (_tour == null || _currentPointIndex >= _tour!.points.length) {
        return; // Tour not loaded or finished
      }

      final currentTargetPoint = _tour!.points[_currentPointIndex];
      final distanceInMeters = Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        currentTargetPoint.latitude,
        currentTargetPoint.longitude,
      );

      setState(() {
          // UPDATED status message
          _statusMessage = "You are ${distanceInMeters.toStringAsFixed(0)} meters away from Point ${_currentPointIndex + 1}";
      });

      // Check if user is within 25 meters and we haven't played this audio yet
      if (distanceInMeters < 25 && !_hasPlayedCurrent) {
        _playAudioForPoint(currentTargetPoint);
      }
    });
  }

  Future<void> _playAudioForPoint(TourPoint point) async {
    setState(() {
      _hasPlayedCurrent = true; // Mark as played to prevent re-triggering
      // UPDATED status message
      _statusMessage = "Playing audio for Point ${_currentPointIndex + 1}";
    });

    try {
      // The audio path from the server is relative, so we build the full URL
      final audioUrl = '$serverBaseUrl/${point.audioFilePath}';
      await _audioPlayer.setUrl(audioUrl);
      _audioPlayer.play();

      // Listen for when the audio completes
      _audioPlayer.playerStateStream.listen((state) {
        if (state.processingState == ProcessingState.completed) {
          // Move to the next point
          setState(() {
            _currentPointIndex++;
            _hasPlayedCurrent = false; // Reset for the next point
            if (_currentPointIndex >= _tour!.points.length) {
                _statusMessage = "Tour completed!";
                _positionStreamSubscription?.cancel();
            } else {
                 _statusMessage = "Audio finished. Walk to the next point.";
                 _goToPoint(_tour!.points[_currentPointIndex]);
            }
          });
        }
      });

    } catch (e) {
        setState(() {
            _statusMessage = "Error playing audio: $e";
        });
    }
  }

  @override
  void dispose() {
    _positionStreamSubscription?.cancel();
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

  /// Duplicated from LocationRecordingScreen to ensure permissions are handled.
  Future<void> _determinePosition() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      setState(() => _statusMessage = 'Location services are disabled.');
      return;
    }
    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        setState(() => _statusMessage = 'Location permissions are denied.');
        return;
      }
    }
    if (permission == LocationPermission.deniedForever) {
      setState(() => _statusMessage = 'Location permissions are permanently denied.');
      return;
    }
  }
}


//-------------------------------------------------
// 4. The Google Maps Screen (Manual Recording)
//-------------------------------------------------
class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => MapScreenState();
}

class MapScreenState extends State<MapScreen> {
  final Completer<GoogleMapController> _controller = Completer<GoogleMapController>();
  static const CameraPosition _kInitialPosition = CameraPosition(
    target: LatLng(40.7128, -74.0060),
    zoom: 14.0,
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Manual Recording'),
        backgroundColor: Colors.green[700],
      ),
      body: GoogleMap(
        mapType: MapType.hybrid,
        initialCameraPosition: _kInitialPosition,
        onMapCreated: (GoogleMapController controller) {
          _controller.complete(controller);
        },
      ),
    );
  }
}

//-------------------------------------------------
// 5. The "Record at Location" Screen
//-------------------------------------------------
class LocationRecordingScreen extends StatefulWidget {
  const LocationRecordingScreen({super.key});

  @override
  State<LocationRecordingScreen> createState() => _LocationRecordingScreenState();
}

class _LocationRecordingScreenState extends State<LocationRecordingScreen> {
  Position? _currentPosition;
  String _statusMessage = 'Fetching location...';
  bool _isRecording = false;

  @override
  void initState() {
    super.initState();
    _determinePosition();
  }

  Future<void> _determinePosition() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      setState(() => _statusMessage = 'Location services are disabled.');
      return;
    }
    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        setState(() => _statusMessage = 'Location permissions are denied.');
        return;
      }
    }
    if (permission == LocationPermission.deniedForever) {
      setState(() => _statusMessage = 'Location permissions are permanently denied.');
      return;
    }
    Geolocator.getPositionStream().listen((Position position) {
      setState(() {
        _currentPosition = position;
        _statusMessage = 'Location found!';
      });
    });
  }

  void _toggleRecording() {
    setState(() {
      _isRecording = !_isRecording;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Live Location Recording'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const Icon(Icons.my_location, size: 60, color: Colors.blue),
            const SizedBox(height: 20),
            Text(
              'CURRENT LOCATION',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 10),
            if (_currentPosition != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Text(
                  'Latitude: ${_currentPosition!.latitude}\nLongitude: ${_currentPosition!.longitude}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 20),
                ),
              )
            else
              Text(
                _statusMessage,
                style: const TextStyle(fontSize: 20),
              ),
            const SizedBox(height: 40),
            ElevatedButton.icon(
              icon: Icon(_isRecording ? Icons.stop : Icons.mic),
              label: Text(_isRecording ? 'Stop Recording' : 'Start Recording'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _isRecording ? Colors.red : Colors.green,
                padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
                textStyle: const TextStyle(fontSize: 20),
              ),
              onPressed: _currentPosition != null ? _toggleRecording : null,
            ),
          ],
        ),
      ),
    );
  }
}
