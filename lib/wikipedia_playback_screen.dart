import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:path_provider/path_provider.dart';
import 'wikipedia_service.dart';
import 'main.dart'; // For ApiService and Tour
import 'local_tour_manager.dart';
import 'storage_preferences.dart';

class WikipediaPlaybackScreen extends StatefulWidget {
  final Position? initialPosition; // null means use current GPS, otherwise use this position

  const WikipediaPlaybackScreen({super.key, this.initialPosition});

  @override
  State<WikipediaPlaybackScreen> createState() => _WikipediaPlaybackScreenState();
}

class _WikipediaPlaybackScreenState extends State<WikipediaPlaybackScreen> {
  final Completer<GoogleMapController> _mapController = Completer();
  final WikipediaService _wikiService = WikipediaService();
  final FlutterTts _tts = FlutterTts();

  StreamSubscription<Position>? _positionStreamSubscription;
  Set<Marker> _markers = {};
  List<WikipediaArticle> _nearbyArticles = [];
  WikipediaArticle? _currentArticle;
  String _statusMessage = 'Searching for nearby places...';
  bool _isPlaying = false;
  bool _isPaused = false;
  int _searchRadiusMeters = 500;
  Position? _currentPosition; // User's actual current GPS position (for real-time tracking)
  Position? _searchCenter; // The location we're searching around (can be different from current position)
  final Set<int> _playedArticleIds = {};
  final Set<int> _disabledArticleIds = {};
  bool _showListView = false;
  WikipediaLanguage _currentLanguage = WikipediaLanguage.languages[0]; // Default to English

  @override
  void initState() {
    super.initState();
    _initializeTts();

    // If we have an initial position, use it as search center
    if (widget.initialPosition != null) {
      _searchCenter = widget.initialPosition;
      _searchNearbyArticles(widget.initialPosition!);
      _startLocationListener(); // Still track user's actual location for map display
    } else {
      // Use current GPS location for both search and tracking
      _startLocationListener();
    }
  }

  Future<void> _initializeTts() async {
    await _tts.setLanguage(_getTtsLanguageCode());
    await _tts.setSpeechRate(0.5);
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);

    _tts.setCompletionHandler(() {
      setState(() {
        _isPlaying = false;
        _isPaused = false;
        _statusMessage = 'Article finished. Walking to next location...';
      });
    });

    _tts.setErrorHandler((message) {
      print('TTS Error: $message');
      setState(() {
        _isPlaying = false;
        _statusMessage = 'Error playing audio';
      });
    });
  }

  String _getTtsLanguageCode() {
    // Map Wikipedia language codes to TTS language codes
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

  void _startLocationListener() async {
    await _determinePosition();

    if (_currentPosition != null) {
      // If no search center was set (no initial position), use current position
      if (_searchCenter == null) {
        _searchCenter = _currentPosition;
        await _searchNearbyArticles(_currentPosition!);
      }

      final controller = await _mapController.future;
      controller.animateCamera(
        CameraUpdate.newLatLngZoom(
          LatLng(_searchCenter!.latitude, _searchCenter!.longitude),
          15,
        ),
      );

      _positionStreamSubscription = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 10,
        ),
      ).listen((position) {
        setState(() {
          _currentPosition = position;
        });

        // Only auto-play if we're using current location mode (no initial position was set)
        if (widget.initialPosition == null && !_isPlaying) {
          _checkProximityAndPlay(position);
        }
      });
    }
  }

  Future<void> _searchNearbyArticles(Position center) async {
    setState(() {
      _statusMessage = 'Searching for places...';
    });

    try {
      _wikiService.setLanguage(_currentLanguage.code);
      final articles = await _wikiService.searchNearby(
        latitude: center.latitude,
        longitude: center.longitude,
        radiusMeters: _searchRadiusMeters,
      );

      setState(() {
        _nearbyArticles = articles;
        _statusMessage = articles.isEmpty
            ? 'No places found nearby'
            : 'Found ${articles.length} places';
        _updateMarkers();
      });
    } catch (e) {
      setState(() {
        _statusMessage = 'Error searching: $e';
      });
    }
  }

  void _updateMarkers() {
    final newMarkers = <Marker>{};

    // Add search center marker (in blue) if it's different from current position
    if (_searchCenter != null && widget.initialPosition != null) {
      newMarkers.add(
        Marker(
          markerId: const MarkerId('search_center'),
          position: LatLng(_searchCenter!.latitude, _searchCenter!.longitude),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
          infoWindow: const InfoWindow(title: 'Search Center'),
        ),
      );
    }

    // Add article markers
    for (final article in _nearbyArticles) {
      final isDisabled = _disabledArticleIds.contains(article.pageId);
      final isPlayed = _playedArticleIds.contains(article.pageId);
      final isCurrent = _currentArticle?.pageId == article.pageId;

      BitmapDescriptor icon;
      if (isDisabled) {
        icon = BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueYellow);
      } else if (isCurrent) {
        icon = BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen);
      } else if (isPlayed) {
        icon = BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueViolet);
      } else {
        icon = BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed);
      }

      newMarkers.add(
        Marker(
          markerId: MarkerId(article.pageId.toString()),
          position: LatLng(article.latitude, article.longitude),
          icon: icon,
          infoWindow: InfoWindow(
            title: article.title,
            snippet: article.extract.length > 50
                ? '${article.extract.substring(0, 50)}...'
                : article.extract,
          ),
          onTap: () => _showArticlePreview(article),
        ),
      );
    }

    setState(() {
      _markers = newMarkers;
    });
  }

  void _checkProximityAndPlay(Position userPosition) {
    if (_nearbyArticles.isEmpty || _isPlaying) return;

    for (final article in _nearbyArticles) {
      if (_disabledArticleIds.contains(article.pageId)) continue;
      if (_playedArticleIds.contains(article.pageId)) continue;

      final distance = Geolocator.distanceBetween(
        userPosition.latitude,
        userPosition.longitude,
        article.latitude,
        article.longitude,
      );

      if (distance < 50) {
        _playArticle(article);
        break;
      }
    }
  }

  Future<void> _playArticle(WikipediaArticle article) async {
    setState(() {
      _currentArticle = article;
      _isPlaying = true;
      _isPaused = false;
      _statusMessage = 'Playing: ${article.title}';
    });

    _updateMarkers();

    String textToRead = article.extract;
    if (textToRead.length < 200) {
      try {
        final fullText = await _wikiService.getFullArticle(article.pageId);
        if (fullText.isNotEmpty) {
          textToRead = fullText;
        }
      } catch (e) {
        print('Could not fetch full article: $e');
      }
    }

    if (textToRead.length > 1000) {
      textToRead = '${textToRead.substring(0, 1000)}...';
    }

    final introduction = 'Now approaching ${article.title}. $textToRead';

    await _tts.speak(introduction);

    _playedArticleIds.add(article.pageId);
  }

  void _pauseResume() async {
    if (_isPaused) {
      await _tts.speak('');
      setState(() {
        _isPaused = false;
      });
    } else {
      await _tts.pause();
      setState(() {
        _isPaused = true;
      });
    }
  }

  void _stopPlayback() async {
    await _tts.stop();
    setState(() {
      _isPlaying = false;
      _isPaused = false;
      _currentArticle = null;
      _statusMessage = 'Playback stopped';
    });
    _updateMarkers();
  }

  void _showArticlePreview(WikipediaArticle article) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        minChildSize: 0.3,
        expand: false,
        builder: (context, scrollController) => Container(
          padding: const EdgeInsets.all(16),
          child: ListView(
            controller: scrollController,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      article.title,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(article.extract),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                icon: const Icon(Icons.play_arrow),
                label: const Text('Play This Article'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                ),
                onPressed: () {
                  Navigator.pop(context);
                  _playArticle(article);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showLanguageSelector() async {
    final selected = await showDialog<WikipediaLanguage>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Select Language'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: WikipediaLanguage.languages.length,
            itemBuilder: (context, index) {
              final lang = WikipediaLanguage.languages[index];
              final isSelected = lang.code == _currentLanguage.code;
              return ListTile(
                title: Text(lang.nativeName),
                subtitle: Text(lang.name),
                trailing: isSelected ? const Icon(Icons.check, color: Colors.green) : null,
                selected: isSelected,
                onTap: () => Navigator.pop(context, lang),
              );
            },
          ),
        ),
      ),
    );

    if (selected != null && selected.code != _currentLanguage.code) {
      setState(() {
        _currentLanguage = selected;
        _nearbyArticles.clear();
        _markers.clear();
        _playedArticleIds.clear();
        _disabledArticleIds.clear();
      });

      await _tts.setLanguage(_getTtsLanguageCode());

      if (_searchCenter != null) {
        await _searchNearbyArticles(_searchCenter!);
      }
    }
  }

  Future<void> _saveWikipediaTourLocally({
  required String name,
  required String description,
  required List<WikipediaArticle> articles,
}) async {
  if (!mounted) return;

  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Saving Locally'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(
            'Saving ${articles.length} articles to device...',
            style: const TextStyle(fontSize: 14),
          ),
        ],
      ),
    ),
  );

  try {
    final localManager = LocalTourManager();

    // Sort articles by distance
    if (_searchCenter != null) {
      articles.sort((a, b) {
        final distA = Geolocator.distanceBetween(
          _searchCenter!.latitude,
          _searchCenter!.longitude,
          a.latitude,
          a.longitude,
        );
        final distB = Geolocator.distanceBetween(
          _searchCenter!.latitude,
          _searchCenter!.longitude,
          b.latitude,
          b.longitude,
        );
        return distA.compareTo(distB);
      });
    }

    // Create tour points with text for TTS
    final waypoints = <TourPoint>[];
    for (int i = 0; i < articles.length; i++) {
      final article = articles[i];
      waypoints.add(
        TourPoint(
          id: i,
          latitude: article.latitude,
          longitude: article.longitude,
          audioFilePath: '',
          name: article.title,
          text: article.extract,
        ),
      );
    }

    // Save locally
    await localManager.saveTour(
      name: name,
      description: description,
      waypoints: waypoints.map((point) => LocalTourWaypoint.fromTourPoint(point)).toList(),
    );

    if (!mounted) return;
    Navigator.pop(context); // Close loading dialog

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(
              child: Text('Wikipedia tour "$name" saved locally! ✓'),
            ),
          ],
        ),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 3),
      ),
    );

    Navigator.of(context).pop();
    Navigator.of(context).pop();

  } catch (e) {
    print('Error saving locally: $e');

    if (!mounted) return;
    Navigator.pop(context);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(
              child: Text('Failed to save: ${e.toString()}'),
            ),
          ],
        ),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 5),
      ),
    );
  }
}

  Future<void> _saveWikipediaTourToServer({
  required String name,
  required String description,
  required List<WikipediaArticle> articles,
}) async {
  int currentStep = 0;
  int totalSteps = articles.length + 1;

  if (!mounted) return;

  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: const Text('Uploading to Server'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(
              'Step $currentStep of $totalSteps',
              style: const TextStyle(fontSize: 14),
            ),
          ],
        ),
      ),
    ),
  );

  try {
    // Sort articles
    if (_searchCenter != null) {
      articles.sort((a, b) {
        final distA = Geolocator.distanceBetween(
          _searchCenter!.latitude,
          _searchCenter!.longitude,
          a.latitude,
          a.longitude,
        );
        final distB = Geolocator.distanceBetween(
          _searchCenter!.latitude,
          _searchCenter!.longitude,
          b.latitude,
          b.longitude,
        );
        return distA.compareTo(distB);
      });
    }

    // Create tour on server
    final apiService = ApiService();
    Tour? newTour;

    int retries = 0;
    const maxRetries = 3;

    while (retries < maxRetries) {
      try {
        newTour = await apiService.createTour(name, description);
        currentStep = 1;
        break;
      } catch (e) {
        retries++;
        if (retries >= maxRetries) {
          throw Exception('Failed after $maxRetries attempts: $e');
        }
        await Future.delayed(Duration(seconds: retries * 2));
      }
    }

    if (newTour == null) {
      throw Exception('Failed to create tour');
    }

    // Upload articles
    for (int i = 0; i < articles.length; i++) {
      final article = articles[i];
      currentStep = i + 2;

      await apiService.createTextWaypoint(
        tourId: newTour.id,
        name: article.title,
        latitude: article.latitude,
        longitude: article.longitude,
        text: article.extract,
      );
    }

    if (!mounted) return;
    Navigator.pop(context);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(
              child: Text('Tour "$name" uploaded! ✓'),
            ),
          ],
        ),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 3),
      ),
    );

    Navigator.of(context).pop();
    Navigator.of(context).pop();

  } catch (e) {
    print('Error uploading: $e');

    if (!mounted) return;
    Navigator.pop(context);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(
              child: Text('Failed to upload: ${e.toString()}'),
            ),
          ],
        ),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 5),
      ),
    );
  }
}

  Future<void> _saveAsCustomTour() async {
  if (_nearbyArticles.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Search for nearby places first.'),
        backgroundColor: Colors.orange,
      ),
    );
    return;
  }

  // Filter out disabled articles
  final articlesToSave = _nearbyArticles
      .where((article) => !_disabledArticleIds.contains(article.pageId))
      .toList();

  if (articlesToSave.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('All articles are disabled. Enable some articles first.'),
        backgroundColor: Colors.orange,
      ),
    );
    return;
  }

  // Check storage preference FIRST
  final storageMode = await StoragePreferences.getStorageMode();
  final isLocalStorage = storageMode == StorageMode.local;

  // Show dialog to get tour name and description
  final nameController = TextEditingController(
    text: 'Wikipedia Tour - ${_currentLanguage.nativeName}',
  );

  // Create description based on whether we're using a custom location or current location
  String locationDescription;
  if (widget.initialPosition != null) {
    locationDescription = 'Wikipedia articles in ${_currentLanguage.nativeName} near ${_searchCenter?.latitude.toStringAsFixed(4)}, ${_searchCenter?.longitude.toStringAsFixed(4)}';
  } else {
    locationDescription = 'Wikipedia articles in ${_currentLanguage.nativeName} near my current location';
  }

  final descController = TextEditingController(text: locationDescription);

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Save Wikipedia Tour'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'This will save ${articlesToSave.length} article${articlesToSave.length != 1 ? 's' : ''} as a custom tour.',
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'Tour Name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: descController,
              decoration: const InputDecoration(
                labelText: 'Description',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isLocalStorage ? Colors.blue.shade50 : Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        isLocalStorage ? Icons.phone_android : Icons.cloud_upload,
                        size: 16,
                        color: isLocalStorage ? Colors.blue : Colors.orange,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        isLocalStorage ? 'Saving Locally' : 'Uploading to Server',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          color: isLocalStorage ? Colors.blue : Colors.orange,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isLocalStorage
                        ? '• Tour will be saved on this device\n'
                          '• Text-to-speech will be used for audio\n'
                          '• No internet required to play\n'
                          '• Tour will be private to you'
                        : '• Tour will be uploaded to the cloud\n'
                          '• Text-to-speech will be used for audio\n'
                          '• Can be accessed from any device\n'
                          '• Can be shared with others',
                    style: const TextStyle(fontSize: 11),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            nameController.dispose();
            descController.dispose();
            Navigator.pop(context, false);
          },
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            Navigator.pop(context, true);
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: isLocalStorage ? Colors.blue : Colors.green,
            foregroundColor: Colors.white,
          ),
          child: Text(isLocalStorage ? 'Save Locally' : 'Upload to Server'),
        ),
      ],
    ),
  );

  if (confirmed != true) {
    nameController.dispose();
    descController.dispose();
    return;
  }

  final tourName = nameController.text.trim();
  final tourDesc = descController.text.trim();
  nameController.dispose();
  descController.dispose();

  if (tourName.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Please enter a tour name.'),
        backgroundColor: Colors.orange,
      ),
    );
    return;
  }

  // Route to appropriate save method based on storage mode
  if (isLocalStorage) {
    await _saveWikipediaTourLocally(
      name: tourName,
      description: tourDesc,
      articles: articlesToSave,
    );
  } else {
    await _saveWikipediaTourToServer(
      name: tourName,
      description: tourDesc,
      articles: articlesToSave,
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
        }
      } else {
        print('TTS synthesis failed with result: $result');
        return null;
      }
    } catch (e) {
      print('Error generating TTS audio for ${article.title}: $e');
      return null;
    }
    return null; // Added return null for cases where file doesn't exist after success
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Text('Wikipedia Tour'),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.3),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                _currentLanguage.code.toUpperCase(),
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        actions: [
          if (_nearbyArticles.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.save),
              onPressed: _saveAsCustomTour,
              tooltip: 'Save as Tour',
            ),
          IconButton(
            icon: const Icon(Icons.language),
            onPressed: _showLanguageSelector,
            tooltip: 'Change Language',
          ),
          IconButton(
            icon: Icon(_showListView ? Icons.map : Icons.list),
            onPressed: () {
              setState(() {
                _showListView = !_showListView;
              });
            },
            tooltip: _showListView ? 'Show Map' : 'Show List',
          ),
          PopupMenuButton<int>(
            icon: const Icon(Icons.tune),
            onSelected: (value) {
              setState(() {
                _searchRadiusMeters = value;
              });
              if (_searchCenter != null) {
                _searchNearbyArticles(_searchCenter!);
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 250,
                child: Text('Search Radius: 250m'),
              ),
              const PopupMenuItem(
                value: 500,
                child: Text('Search Radius: 500m'),
              ),
              const PopupMenuItem(
                value: 1000,
                child: Text('Search Radius: 1km'),
              ),
              const PopupMenuItem(
                value: 2000,
                child: Text('Search Radius: 2km'),
              ),
            ],
          ),
        ],
      ),
      body: _showListView ? _buildListView() : _buildMapView(),
    );
  }

  Widget _buildMapView() {
    return Stack(
        children: [
          GoogleMap(
            onMapCreated: (controller) => _mapController.complete(controller),
            initialCameraPosition: const CameraPosition(
              target: LatLng(37.7749, -122.4194),
              zoom: 15,
            ),
            markers: _markers,
            myLocationEnabled: true,
            myLocationButtonEnabled: true,
            mapType: MapType.normal,
          ),
          Positioned(
            top: 16,
            left: 16,
            right: 16,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Icon(
                          _isPlaying ? Icons.volume_up : Icons.search,
                          color: _isPlaying ? Colors.green : Colors.blue,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _statusMessage,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                    if (_nearbyArticles.isNotEmpty)
                      Column(
                        children: [
                          Text(
                            'Found ${_nearbyArticles.length} places within ${_searchRadiusMeters}m',
                            style: const TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                'Language: ${_currentLanguage.nativeName}',
                                style: const TextStyle(fontSize: 11, color: Colors.blue),
                              ),
                              if (_disabledArticleIds.isNotEmpty)
                                Text(
                                  ' • ${_disabledArticleIds.length} disabled',
                                  style: const TextStyle(fontSize: 11, color: Colors.orange),
                                ),
                            ],
                          ),
                          if (widget.initialPosition != null)
                            Text(
                              '📍 Custom location search',
                              style: TextStyle(fontSize: 11, color: Colors.orange.shade700, fontWeight: FontWeight.bold),
                            ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ),
          if (_isPlaying)
            Positioned(
              bottom: 16,
              left: 16,
              right: 16,
              child: Card(
                elevation: 8,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _currentArticle?.title ?? '',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          IconButton(
                            icon: Icon(_isPaused ? Icons.play_arrow : Icons.pause),
                            iconSize: 32,
                            color: Colors.blue,
                            onPressed: _pauseResume,
                          ),
                          IconButton(
                            icon: const Icon(Icons.stop),
                            iconSize: 32,
                            color: Colors.red,
                            onPressed: _stopPlayback,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      );
  }

  Widget _buildListView() {
    final sortedArticles = List<WikipediaArticle>.from(_nearbyArticles);
    final Position centerForDistance = _searchCenter ?? _currentPosition!;

    sortedArticles.sort((a, b) {
      final distA = Geolocator.distanceBetween(
        centerForDistance.latitude,
        centerForDistance.longitude,
        a.latitude,
        a.longitude,
      );
      final distB = Geolocator.distanceBetween(
        centerForDistance.latitude,
        centerForDistance.longitude,
        b.latitude,
        b.longitude,
      );
      return distA.compareTo(distB);
    });

    return Column(
      children: [
        Card(
          margin: const EdgeInsets.all(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      _isPlaying ? Icons.volume_up : Icons.list,
                      color: _isPlaying ? Colors.green : Colors.blue,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _statusMessage,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                if (_nearbyArticles.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Found ${_nearbyArticles.length} places • Language: ${_currentLanguage.nativeName}',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  if (widget.initialPosition != null)
                    Text(
                      '📍 Searching at custom location',
                      style: TextStyle(fontSize: 12, color: Colors.orange.shade700, fontWeight: FontWeight.bold),
                    ),
                ],
              ],
            ),
          ),
        ),
        Expanded(
          child: _nearbyArticles.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.search_off, size: 64, color: Colors.grey),
                      const SizedBox(height: 16),
                      Text('No articles found in ${_currentLanguage.nativeName}'),
                      const SizedBox(height: 8),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.language),
                        label: const Text('Try Another Language'),
                        onPressed: _showLanguageSelector,
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'or increase the search radius',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: sortedArticles.length,
                  itemBuilder: (context, index) {
                    final article = sortedArticles[index];
                    final isDisabled = _disabledArticleIds.contains(article.pageId);
                    final isPlayed = _playedArticleIds.contains(article.pageId);
                    final isCurrent = _currentArticle?.pageId == article.pageId;

                    final distance = Geolocator.distanceBetween(
                      centerForDistance.latitude,
                      centerForDistance.longitude,
                      article.latitude,
                      article.longitude,
                    );

                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      elevation: isCurrent ? 4 : 1,
                      color: isCurrent
                          ? Colors.green.shade50
                          : isDisabled
                              ? Colors.grey.shade100
                              : null,
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: isCurrent
                              ? Colors.green
                              : isDisabled
                                  ? Colors.grey
                                  : isPlayed
                                      ? Colors.purple
                                      : Colors.red,
                          child: Icon(
                            isDisabled
                                ? Icons.block
                                : isPlayed
                                    ? Icons.check
                                    : Icons.article,
                            color: Colors.white,
                          ),
                        ),
                        title: Text(
                          article.title,
                          style: TextStyle(
                            fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                            color: isDisabled ? Colors.grey : null,
                          ),
                        ),
                        subtitle: Text(
                          '${(distance).toStringAsFixed(0)}m away',
                          style: TextStyle(
                            fontSize: 12,
                            color: isDisabled ? Colors.grey : Colors.blue,
                          ),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (!isCurrent)
                              IconButton(
                                icon: Icon(
                                  isDisabled ? Icons.visibility : Icons.visibility_off,
                                  color: isDisabled ? Colors.grey : Colors.orange,
                                ),
                                onPressed: () {
                                  setState(() {
                                    if (isDisabled) {
                                      _disabledArticleIds.remove(article.pageId);
                                    } else {
                                      _disabledArticleIds.add(article.pageId);
                                    }
                                    _updateMarkers();
                                  });
                                },
                              ),
                            if (isCurrent)
                              const Icon(Icons.volume_up, color: Colors.green),
                          ],
                        ),
                        onTap: () => _showArticlePreview(article),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Future<void> _determinePosition() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      setState(() => _statusMessage = 'Location services are disabled.');
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
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

    try {
      _currentPosition = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
    } catch (e) {
      setState(() => _statusMessage = 'Error getting position: $e');
    }
  }

  @override
  void dispose() {
    _positionStreamSubscription?.cancel();
    _tts.stop();
    super.dispose();
  }
}
