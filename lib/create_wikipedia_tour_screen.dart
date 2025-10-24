// File: lib/create_wikipedia_tour_screen.dart
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:path_provider/path_provider.dart';
import 'wikipedia_service.dart';
import 'main.dart';
import 'storage_preferences.dart';
import 'local_tour_manager.dart';

enum LocationMethod { gps, address, map }

class CreateWikipediaTourScreen extends StatefulWidget {
  const CreateWikipediaTourScreen({super.key});

  @override
  State<CreateWikipediaTourScreen> createState() => _CreateWikipediaTourScreenState();
}

class _CreateWikipediaTourScreenState extends State<CreateWikipediaTourScreen> {
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _addressController = TextEditingController();
  final WikipediaService _wikiService = WikipediaService();
  final FlutterTts _tts = FlutterTts();

  String _status = 'Select a location method...';
  Position? _position;
  LocationMethod _locationMethod = LocationMethod.gps;
  bool _isGeocodingAddress = false;
  bool _isLoadingLocation = false;
  int _searchRadiusMeters = 1000;
  WikipediaLanguage _currentLanguage = WikipediaLanguage.languages[0];
  StorageMode _selectedStorageMode = StorageMode.local; // Track selected storage mode (default: local)

  final Completer<GoogleMapController> _mapController = Completer();
  LatLng? _selectedMapLocation;
  Set<Marker> _markers = {};

  @override
  void initState() {
    super.initState();
    _initializeTts();
    _loadStoragePreference(); // NEW: Load user's saved preference
  }

  // NEW: Load the user's saved storage preference
  Future<void> _loadStoragePreference() async {
    final savedMode = await StoragePreferences.getStorageMode();
    setState(() {
      _selectedStorageMode = savedMode;
    });
  }

  Future<void> _initializeTts() async {
    await _tts.setLanguage(_getTtsLanguageCode());
    await _tts.setSpeechRate(0.5);
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);
  }

  String _getTtsLanguageCode() {
    final ttsMap = {
      'en': 'en-US',
      'es': 'es-ES',
      'fr': 'fr-FR',
      'de': 'de-DE',
      'it': 'it-IT',
      'pt': 'pt-PT',
      'ru': 'ru-RU',
      'ja': 'ja-JP',
      'zh': 'zh-CN',
      'ar': 'ar-SA',
      'hi': 'hi-IN',
      'ko': 'ko-KR',
      'nl': 'nl-NL',
      'pl': 'pl-PL',
      'tr': 'tr-TR',
      'sv': 'sv-SE',
      'no': 'no-NO',
      'da': 'da-DK',
      'fi': 'fi-FI',
      'he': 'he-IL',
    };
    return ttsMap[_currentLanguage.code] ?? 'en-US';
  }

  Future<void> _getCurrentLocation() async {
    setState(() {
      _isLoadingLocation = true;
      _status = 'Getting your current location...';
    });

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() {
          _status = 'Location services are disabled. Please enable them.';
          _isLoadingLocation = false;
        });
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          setState(() {
            _status = 'Location permissions are denied.';
            _isLoadingLocation = false;
          });
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        setState(() {
          _status = 'Location permissions are permanently denied.';
          _isLoadingLocation = false;
        });
        return;
      }

      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      setState(() {
        _position = position;
        _status = 'Location found: ${position.latitude.toStringAsFixed(4)}, ${position.longitude.toStringAsFixed(4)}';
        _isLoadingLocation = false;
      });

      // Move map camera if map is being used
      if (_locationMethod == LocationMethod.map) {
        final controller = await _mapController.future;
        controller.animateCamera(
          CameraUpdate.newLatLngZoom(
            LatLng(position.latitude, position.longitude),
            15,
          ),
        );
        _updateMarker(position.latitude, position.longitude);
      }
    } catch (e) {
      setState(() {
        _status = 'Error getting location: $e';
        _isLoadingLocation = false;
      });
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
        return;
      }

      final location = locations.first;
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
        _status = 'Address found: ${location.latitude.toStringAsFixed(4)}, ${location.longitude.toStringAsFixed(4)}';
        _isGeocodingAddress = false;
      });

      // Move map camera if map is being used
      if (_locationMethod == LocationMethod.map) {
        final controller = await _mapController.future;
        controller.animateCamera(
          CameraUpdate.newLatLngZoom(
            LatLng(location.latitude, location.longitude),
            15,
          ),
        );
        _updateMarker(location.latitude, location.longitude);
      }
    } catch (e) {
      setState(() {
        _status = 'Error geocoding address: $e';
        _isGeocodingAddress = false;
      });
    }
  }

  void _updateMarker(double lat, double lon) {
    setState(() {
      _selectedMapLocation = LatLng(lat, lon);
      _markers = {
        Marker(
          markerId: const MarkerId('selected_location'),
          position: LatLng(lat, lon),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
        ),
      };
    });
  }

  void _onMapTap(LatLng position) {
    setState(() {
      _position = Position(
        latitude: position.latitude,
        longitude: position.longitude,
        timestamp: DateTime.now(),
        accuracy: 0,
        altitude: 0,
        altitudeAccuracy: 0,
        heading: 0,
        headingAccuracy: 0,
        speed: 0,
        speedAccuracy: 0,
      );
      _status = 'Selected location: ${position.latitude.toStringAsFixed(4)}, ${position.longitude.toStringAsFixed(4)}';
    });
    _updateMarker(position.latitude, position.longitude);
  }

  void _showLanguageSelector() async {
    final selected = await showDialog<WikipediaLanguage>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Select Language'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: WikipediaLanguage.languages.map((lang) {
              return ListTile(
                title: Text(lang.nativeName),
                subtitle: Text(lang.englishName),
                trailing: _currentLanguage.code == lang.code
                    ? const Icon(Icons.check, color: Colors.green)
                    : null,
                onTap: () => Navigator.pop(context, lang),
              );
            }).toList(),
          ),
        ),
      ),
    );

    if (selected != null) {
      setState(() {
        _currentLanguage = selected;
      });
      await _tts.setLanguage(_getTtsLanguageCode());
    }
  }

  void _createTour() async {
    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a tour name'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Show loading dialog with progress
    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Creating Wikipedia Tour'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              const Text(
                'Searching for Wikipedia articles...',
                style: TextStyle(fontSize: 14),
              ),
            ],
          ),
        ),
      ),
    );

    try {
      // Step 1: Search for Wikipedia articles
      final articles = await _wikiService.searchNearby(
        latitude: _position!.latitude,
        longitude: _position!.longitude,
        radiusMeters: _searchRadiusMeters,
        limit: 20,
      );

      if (articles.isEmpty) {
        if (!mounted) return;
        Navigator.pop(context); // Close loading dialog

        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('No Articles Found'),
            content: Text(
              'No Wikipedia articles found in ${_currentLanguage.nativeName} within ${_searchRadiusMeters}m of the selected location.\n\nTry:\n• Increasing the search radius\n• Selecting a different location\n• Changing the language',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          ),
        );
        return;
      }

      // Update loading dialog
      if (!mounted) return;
      Navigator.pop(context);

      // Show preview and confirmation dialog WITH STORAGE SELECTION
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Confirm Tour Creation'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Found ${articles.length} Wikipedia article${articles.length != 1 ? 's' : ''} in ${_currentLanguage.nativeName}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Tour Name',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _descriptionController,
                  decoration: InputDecoration(
                    labelText: 'Description (optional)',
                    border: const OutlineInputBorder(),
                    hintText: 'Wikipedia articles near ${_position!.latitude.toStringAsFixed(4)}, ${_position!.longitude.toStringAsFixed(4)}',
                  ),
                  maxLines: 3,
                ),
                const SizedBox(height: 16),

                // NEW: STORAGE SELECTION UI
                const Text(
                  'Storage Location:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    children: [
                      RadioListTile<StorageMode>(
                        title: const Row(
                          children: [
                            Icon(Icons.phone_android, size: 20, color: Colors.blue),
                            SizedBox(width: 8),
                            Text('Save Locally on Device'),
                          ],
                        ),
                        subtitle: const Text(
                          '• Private to you\n• No internet required to play\n• Uses device storage',
                          style: TextStyle(fontSize: 11),
                        ),
                        value: StorageMode.local,
                        groupValue: _selectedStorageMode,
                        onChanged: (StorageMode? value) {
                          setState(() {
                            _selectedStorageMode = value!;
                          });
                        },
                      ),
                      Divider(height: 1, color: Colors.grey.shade300),
                      RadioListTile<StorageMode>(
                        title: const Row(
                          children: [
                            Icon(Icons.cloud_upload, size: 20, color: Colors.green),
                            SizedBox(width: 8),
                            Text('Upload to Server'),
                          ],
                        ),
                        subtitle: const Text(
                          '• Accessible from any device\n• Can be shared with others\n• Requires internet',
                          style: TextStyle(fontSize: 11),
                        ),
                        value: StorageMode.server,
                        groupValue: _selectedStorageMode,
                        onChanged: (StorageMode? value) {
                          setState(() {
                            _selectedStorageMode = value!;
                          });
                        },
                      ),
                    ],
                  ),
                ),
                // END STORAGE SELECTION UI

                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.info_outline, size: 16, color: Colors.blue),
                          SizedBox(width: 4),
                          Text(
                            'Tour Details:',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '• ${articles.length} waypoints will be created\n'
                        '• Text-to-speech audio will be generated\n'
                        '• Search radius: ${_searchRadiusMeters}m\n'
                        '• Language: ${_currentLanguage.nativeName}',
                        style: const TextStyle(fontSize: 11),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Articles to include:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                ),
                const SizedBox(height: 8),
                Container(
                  constraints: const BoxConstraints(maxHeight: 200),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: articles.length,
                    itemBuilder: (context, index) {
                      final article = articles[index];
                      final distance = Geolocator.distanceBetween(
                        _position!.latitude,
                        _position!.longitude,
                        article.latitude,
                        article.longitude,
                      );
                      return ListTile(
                        dense: true,
                        leading: CircleAvatar(
                          radius: 12,
                          backgroundColor: Colors.blue,
                          child: Text(
                            '${index + 1}',
                            style: const TextStyle(fontSize: 10, color: Colors.white),
                          ),
                        ),
                        title: Text(
                          article.title,
                          style: const TextStyle(fontSize: 12),
                        ),
                        subtitle: Text(
                          '${distance.toStringAsFixed(0)}m away',
                          style: const TextStyle(fontSize: 10),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: _selectedStorageMode == StorageMode.local
                    ? Colors.blue
                    : Colors.green,
                foregroundColor: Colors.white,
              ),
              child: Text(_selectedStorageMode == StorageMode.local
                  ? 'Save Locally'
                  : 'Upload to Server'),
            ),
          ],
        ),
      );

      if (confirmed != true) return;

      final tourName = _nameController.text.trim();
      final tourDesc = _descriptionController.text.trim().isEmpty
          ? 'Wikipedia articles near ${_position!.latitude.toStringAsFixed(4)}, ${_position!.longitude.toStringAsFixed(4)}'
          : _descriptionController.text.trim();

      // Save the user's storage preference for next time
      await StoragePreferences.setStorageMode(_selectedStorageMode);

      // Route to appropriate save method based on storage mode
      if (_selectedStorageMode == StorageMode.local) {
        await _createTourLocally(tourName, tourDesc, articles);
      } else {
        await _createTourOnServer(tourName, tourDesc, articles);
      }

    } catch (e, stackTrace) {
      print('Error in tour creation process: $e');
      print('Stack trace: $stackTrace');

      if (!mounted) return;
      Navigator.pop(context); // Close any open dialog

      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Error'),
          content: Text('Failed to create tour: $e'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  // NEW: Create tour locally on device
  Future<void> _createTourLocally(String tourName, String tourDesc, List<WikipediaArticle> articles) async {
    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        title: Text('Saving Locally'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Saving tour to your device...'),
          ],
        ),
      ),
    );

    try {
      final localManager = LocalTourManager();

      // Create tour waypoints with text for TTS
      final waypoints = articles.map((article) {
        return LocalTourWaypoint(
          name: article.title,
          latitude: article.latitude,
          longitude: article.longitude,
          text: article.extract, // Store text for TTS generation during playback
        );
      }).toList();

      await localManager.saveTour(
        name: tourName,
        description: tourDesc,
        waypoints: waypoints,
      );

      if (!mounted) return;
      Navigator.pop(context); // Close loading dialog
      Navigator.pop(context); // Go back to previous screen

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(
                child: Text('Tour "$tourName" saved locally! ✓'),
              ),
            ],
          ),
          backgroundColor: Colors.blue,
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (e) {
      print('Error saving tour locally: $e');

      if (!mounted) return;
      Navigator.pop(context); // Close loading dialog

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to save tour locally: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  // EXISTING: Create tour on server (with modifications)
  Future<void> _createTourOnServer(String tourName, String tourDesc, List<WikipediaArticle> articles) async {
    if (!mounted) return;

    int currentStep = 0;
    int totalSteps = articles.length + 1;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Creating Tour'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                Text(
                  'Step $currentStep of $totalSteps',
                  style: const TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 8),
                Text(
                  currentStep == 0
                      ? 'Creating tour on server...'
                      : currentStep <= articles.length
                          ? 'Generating audio ${currentStep}/${articles.length}...'
                          : 'Complete!',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          );
        },
      ),
    );

    try {
      // Step 2: Create tour on server
      final apiService = ApiService();
      final tourResponse = await apiService.createTour(tourName, tourDesc);
      final tourId = tourResponse.id;

      currentStep = 1;
      if (mounted) {
        Navigator.pop(context);
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Creating Tour'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                Text(
                  'Step $currentStep of $totalSteps',
                  style: const TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 8),
                Text(
                  'Generating audio ${currentStep}/${articles.length}...',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
        );
      }

      // Step 3: Generate audio and create waypoints for each article
      for (int i = 0; i < articles.length; i++) {
        final article = articles[i];

        // Generate TTS audio
        final audioPath = await _generateTtsAudio(article, i);

        if (audioPath == null) {
          print('Failed to generate audio for ${article.title}, skipping...');
          continue;
        }

        // Upload waypoint with audio to server
        await apiService.createWaypoint(
          tourId: tourId,
          name: article.title,
          latitude: article.latitude,
          longitude: article.longitude,
          audioFilePath: audioPath,
        );

        // Update progress
        currentStep = i + 2;
        if (mounted) {
          Navigator.pop(context);
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (dialogContext) => AlertDialog(
              title: const Text('Creating Tour'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(
                    'Step $currentStep of $totalSteps',
                    style: const TextStyle(fontSize: 14),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    currentStep <= articles.length
                        ? 'Generating audio ${currentStep}/${articles.length}...'
                        : 'Complete!',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
          );
        }
      }

      // Success!
      if (!mounted) return;
      Navigator.pop(context); // Close progress dialog
      Navigator.pop(context); // Go back to previous screen

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Tour "$tourName" created successfully with ${articles.length} waypoints!'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 3),
          action: SnackBarAction(
            label: 'View Tours',
            textColor: Colors.white,
            onPressed: () {
              Navigator.pop(context); // Go back to main menu
            },
          ),
        ),
      );
    } catch (e, stackTrace) {
      print('Error creating tour: $e');
      print('Stack trace: $stackTrace');

      if (!mounted) return;
      Navigator.pop(context); // Close loading dialog

      String errorMessage = 'Failed to create tour: $e';
      if (e.toString().contains('Connection closed') ||
          e.toString().contains('TimeoutException')) {
        errorMessage =
            'Server connection timeout. The server may be starting up. Please try again in a minute.';
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMessage),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
          action: SnackBarAction(
            label: 'Retry',
            textColor: Colors.white,
            onPressed: () {
              _createTour();
            },
          ),
        ),
      );
    }
  }

  Future<String?> _generateTtsAudio(WikipediaArticle article, int index) async {
    try {
      // Get full article text if extract is too short
      String textToRead = article.extract;
      if (textToRead.length < 200) {
        try {
          final fullText = await _wikiService.getFullArticle(article.pageId);
          if (fullText.isNotEmpty) {
            textToRead = fullText;
          }
        } catch (e) {
          print('Could not fetch full article, using extract: $e');
        }
      }

      // Limit text length to avoid very long audio files
      if (textToRead.length > 1000) {
        textToRead = '${textToRead.substring(0, 1000)}...';
      }

      // Create introduction
      final introduction = 'Now approaching ${article.title}. $textToRead';

      // Generate audio file using TTS with proper path
      final directory = await getApplicationDocumentsDirectory();
      final fileName = 'wiki_tts_${DateTime.now().millisecondsSinceEpoch}_$index.wav';
      final filePath = '${directory.path}/$fileName';

      print('Generating TTS audio to: $filePath');

      final result = await _tts.synthesizeToFile(introduction, filePath);

      if (result == 1) {
        print('TTS synthesis successful');
        // Verify file was created
        final file = File(filePath);
        if (await file.exists()) {
          final size = await file.length();
          print('Audio file created: $filePath (${size} bytes)');
          return filePath;
        } else {
          print('TTS synthesis returned success but file not found');
          return null;
        }
      } else {
        print('TTS synthesis failed with result: $result');
        return null;
      }
    } catch (e) {
      print('Error generating TTS audio for ${article.title}: $e');
      return null;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _addressController.dispose();
    _tts.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Wikipedia Tour'),
        actions: [
          IconButton(
            icon: const Icon(Icons.language),
            onPressed: _showLanguageSelector,
            tooltip: 'Change Language',
          ),
          PopupMenuButton<int>(
            icon: const Icon(Icons.tune),
            onSelected: (value) {
              setState(() {
                _searchRadiusMeters = value;
              });
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 500,
                child: Text('500m radius ${_searchRadiusMeters == 500 ? "✓" : ""}'),
              ),
              PopupMenuItem(
                value: 1000,
                child: Text('1km radius ${_searchRadiusMeters == 1000 ? "✓" : ""}'),
              ),
              PopupMenuItem(
                value: 2000,
                child: Text('2km radius ${_searchRadiusMeters == 2000 ? "✓" : ""}'),
              ),
              PopupMenuItem(
                value: 5000,
                child: Text('5km radius ${_searchRadiusMeters == 5000 ? "✓" : ""}'),
              ),
            ],
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Status message
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Row(
                children: [
                  Icon(
                    _position != null ? Icons.check_circle : Icons.info_outline,
                    color: _position != null ? Colors.green : Colors.blue,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _status,
                      style: const TextStyle(fontSize: 14),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Location method selector
            const Text(
              'Select Location Method:',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            SegmentedButton<LocationMethod>(
              segments: const [
                ButtonSegment(
                  value: LocationMethod.gps,
                  label: Text('GPS'),
                  icon: Icon(Icons.my_location),
                ),
                ButtonSegment(
                  value: LocationMethod.address,
                  label: Text('Address'),
                  icon: Icon(Icons.location_city),
                ),
                ButtonSegment(
                  value: LocationMethod.map,
                  label: Text('Map'),
                  icon: Icon(Icons.map),
                ),
              ],
              selected: {_locationMethod},
              onSelectionChanged: (Set<LocationMethod> newSelection) {
                setState(() {
                  _locationMethod = newSelection.first;
                });
              },
            ),
            const SizedBox(height: 16),

            // Location method specific UI
            if (_locationMethod == LocationMethod.gps) ...[
              ElevatedButton.icon(
                onPressed: _isLoadingLocation ? null : _getCurrentLocation,
                icon: _isLoadingLocation
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.my_location),
                label: Text(_isLoadingLocation ? 'Getting Location...' : 'Use Current Location'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ] else if (_locationMethod == LocationMethod.address) ...[
              TextField(
                controller: _addressController,
                decoration: const InputDecoration(
                  labelText: 'Enter Address',
                  hintText: 'e.g., 1600 Amphitheatre Parkway, Mountain View, CA',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.location_city),
                ),
              ),
              const SizedBox(height: 8),
              ElevatedButton.icon(
                onPressed: _isGeocodingAddress ? null : _geocodeAddress,
                icon: _isGeocodingAddress
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.search),
                label: Text(_isGeocodingAddress ? 'Searching...' : 'Search Address'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ] else if (_locationMethod == LocationMethod.map) ...[
              Container(
                height: 300,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: GoogleMap(
                    initialCameraPosition: CameraPosition(
                      target: _position != null
                          ? LatLng(_position!.latitude, _position!.longitude)
                          : const LatLng(37.7749, -122.4194), // Default: San Francisco
                      zoom: 13,
                    ),
                    markers: _markers,
                    onMapCreated: (GoogleMapController controller) {
                      _mapController.complete(controller);
                    },
                    onTap: _onMapTap,
                    myLocationEnabled: true,
                    myLocationButtonEnabled: true,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Tap on the map to select a location',
                style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
            ],

            const SizedBox(height: 24),

            // Create tour button
            ElevatedButton.icon(
              onPressed: _position != null ? _createTour : null,
              icon: const Icon(Icons.add_location),
              label: const Text('Create Wikipedia Tour'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                disabledBackgroundColor: Colors.grey.shade300,
                disabledForegroundColor: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 12),

            // Help text
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.amber.shade200),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.lightbulb_outline, size: 16, color: Colors.amber),
                      SizedBox(width: 4),
                      Text(
                        'How it works:',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                    ],
                  ),
                  SizedBox(height: 4),
                  Text(
                    '1. Select a location method (GPS, Address, or Map)\n'
                    '2. Choose your preferred language and search radius\n'
                    '3. The app will find Wikipedia articles near that location\n'
                    '4. Choose where to save: Locally or on the Server\n'
                    '5. Audio will be generated using text-to-speech\n'
                    '6. The tour will be saved and ready to play!',
                    style: TextStyle(fontSize: 11),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
