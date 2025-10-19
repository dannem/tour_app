import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:path_provider/path_provider.dart';
import 'wikipedia_service.dart';
import 'main.dart'; // For ApiService and Tour

class WikipediaPlaybackScreen extends StatefulWidget {
  const WikipediaPlaybackScreen({super.key});

  @override
  State<WikipediaPlaybackScreen> createState() => _WikipediaPlaybackScreenState();
}

class _WikipediaPlaybackScreenState extends State<WikipediaPlaybackScreen> {
  bool _isDisposed = false;
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
  Position? _currentPosition;
  final Set<int> _playedArticleIds = {};
  final Set<int> _disabledArticleIds = {};
  bool _showListView = false;
  WikipediaLanguage _currentLanguage = WikipediaLanguage.languages[0]; // Default to English

  void _safeSetState(VoidCallback fn) {
    if (mounted && !_isDisposed) {
      setState(fn);
      }
    }
  @override
  void initState() {
    super.initState();
    _initializeTts();
    _startLocationListener();
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

  Future<void> _changeLanguage(WikipediaLanguage newLanguage) async {
    // Stop any current playback
    if (_isPlaying) {
      await _stopPlayback();
    }

    setState(() {
      _currentLanguage = newLanguage;
      _nearbyArticles.clear();
      _playedArticleIds.clear();
      _disabledArticleIds.clear();
      _markers = {};
      _statusMessage = 'Switching to ${newLanguage.nativeName}...';
    });

    // Update Wikipedia service language
    _wikiService.setLanguage(newLanguage.code);

    // Update TTS language
    await _tts.setLanguage(_getTtsLanguageCode());

    // Refresh articles in new language
    if (_currentPosition != null) {
      await _searchNearbyArticles(_currentPosition!);
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Language changed to ${newLanguage.nativeName}'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void _showLanguageSelector() {
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Select Language',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
            ),
            const Divider(),
            Expanded(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: WikipediaLanguage.languages.length,
                itemBuilder: (context, index) {
                  final language = WikipediaLanguage.languages[index];
                  final isSelected = language.code == _currentLanguage.code;

                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: isSelected ? Colors.blue : Colors.grey.shade300,
                      child: Text(
                        language.code.toUpperCase(),
                        style: TextStyle(
                          color: isSelected ? Colors.white : Colors.black,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    title: Text(
                      language.nativeName,
                      style: TextStyle(
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                    subtitle: Text(language.name),
                    trailing: isSelected
                        ? const Icon(Icons.check, color: Colors.blue)
                        : null,
                    onTap: () {
                      Navigator.pop(context);
                      _changeLanguage(language);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _startLocationListener() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      setState(() {
        _statusMessage = 'Location services are disabled';
      });
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        setState(() {
          _statusMessage = 'Location permission denied';
        });
        return;
      }
    }

    _positionStreamSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
      ),
    ).listen((Position position) {
      _currentPosition = position;

      if (_nearbyArticles.isEmpty) {
        _searchNearbyArticles(position);
      }

      _checkProximityToArticles(position);
      _updateMarkers();
      _moveCamera(position);
    });
  }

  Future<void> _searchNearbyArticles(Position position) async {
    if (_isDisposed || !mounted) return; // Add this check

    try {
      final articles = await _wikiService.searchNearby(
        latitude: position.latitude,
        longitude: position.longitude,
        radiusMeters: _searchRadiusMeters,
        limit: 20,
      );

      if (_isDisposed || !mounted) return; // Add this check after async

      setState(() {
        _nearbyArticles = articles;
        _updateMarkers();
        if (!_isPlaying && articles.isNotEmpty) {
          _statusMessage = 'Found ${articles.length} nearby places';
        } else if (articles.isEmpty) {
          _statusMessage = 'No articles found in ${_currentLanguage.nativeName}. Try another language or increase radius.';
        }
      });
    } catch (e) {
      print('Error searching Wikipedia: $e');
    }
  }

  Future<void> _moveCamera(Position position) async {
    final controller = await _mapController.future;
    controller.animateCamera(
      CameraUpdate.newLatLng(
        LatLng(position.latitude, position.longitude),
      ),
    );
  }

  void _updateMarkers() {
    _markers = _nearbyArticles.map((article) {
      final isCurrent = _currentArticle?.pageId == article.pageId;
      final isPlayed = _playedArticleIds.contains(article.pageId);
      final isDisabled = _disabledArticleIds.contains(article.pageId);

      return Marker(
        markerId: MarkerId(article.pageId.toString()),
        position: LatLng(article.latitude, article.longitude),
        infoWindow: InfoWindow(
          title: article.title,
          snippet: article.extract.length > 100
              ? '${article.extract.substring(0, 100)}...'
              : article.extract,
        ),
        icon: isCurrent
            ? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen)
            : isDisabled
                ? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueYellow)
            : isPlayed
                ? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueViolet)
                : BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        onTap: () => _showArticlePreview(article),
      );
    }).toSet();
  }

  void _checkProximityToArticles(Position position) {
    for (final article in _nearbyArticles) {
      if (_playedArticleIds.contains(article.pageId) ||
          _disabledArticleIds.contains(article.pageId)) {
        continue;
      }

      final distance = Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
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
      _playedArticleIds.add(article.pageId);
      _updateMarkers();
    });

    String textToRead = article.extract;
    if (textToRead.length < 200) {
      textToRead = await _wikiService.getFullArticle(article.pageId);
    }

    final introduction = 'Now approaching ${article.title}. $textToRead';
    await _tts.speak(introduction);
  }

  Future<void> _pauseResume() async {
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

  Future<void> _stopPlayback() async {
    await _tts.stop();
    setState(() {
      _isPlaying = false;
      _isPaused = false;
      _currentArticle = null;
      _statusMessage = 'Playback stopped';
      _updateMarkers();
    });
  }

  void _showArticlePreview(WikipediaArticle article) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                article.title,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: SingleChildScrollView(
                  controller: scrollController,
                  child: Text(article.extract),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      _playArticle(article);
                    },
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Play'),
                  ),
                  ElevatedButton.icon(
                    onPressed: () {
                      setState(() {
                        if (_disabledArticleIds.contains(article.pageId)) {
                          _disabledArticleIds.remove(article.pageId);
                        } else {
                          _disabledArticleIds.add(article.pageId);
                        }
                        _updateMarkers();
                      });
                      Navigator.pop(context);
                    },
                    icon: Icon(_disabledArticleIds.contains(article.pageId)
                        ? Icons.visibility
                        : Icons.visibility_off),
                    label: Text(_disabledArticleIds.contains(article.pageId)
                        ? 'Enable'
                        : 'Disable'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }


Future<void> _saveAsCustomTour() async {
  // Get list of articles to save (not disabled)
  final articlesToSave = _nearbyArticles
      .where((article) => !_disabledArticleIds.contains(article.pageId))
      .toList();

  if (articlesToSave.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('No articles selected. Please enable at least one article.'),
        backgroundColor: Colors.orange,
      ),
    );
    return;
  }

  // Show dialog to get tour name and description
  final nameController = TextEditingController(text: 'Wikipedia Tour');
  final descController = TextEditingController(
    text: 'Discover ${articlesToSave.length} interesting places near you',
  );


  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Save Wikipedia Tour'),
      content: SizedBox(
        width: double.maxFinite,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.6,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ... content ...
              ],
            ),
          ),
        ),
      ),
      actions: [ /* ... */ ],
    ),
  );
  if (confirmed != true) {
    nameController.dispose();
    descController.dispose();
    return;
  }

  final tourName = nameController.text;
  final tourDesc = descController.text;
  nameController.dispose();
  descController.dispose();

  // Show loading dialog with progress
  if (!mounted) return;

  int currentStep = 0;
  int totalSteps = articlesToSave.length + 1; // +1 for creating tour

  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: const Text('Saving Wikipedia Tour'),
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
                  : currentStep <= articlesToSave.length
                      ? 'Saving waypoint ${currentStep}/${articlesToSave.length}...'
                      : 'Complete!',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
    ),
  ).then((_) {
    // Dialog dismissed callback
  });

  try {
    // Sort articles by distance
    if (_currentPosition != null) {
      articlesToSave.sort((a, b) {
        final distA = Geolocator.distanceBetween(
          _currentPosition!.latitude,
          _currentPosition!.longitude,
          a.latitude,
          a.longitude,
        );
        final distB = Geolocator.distanceBetween(
          _currentPosition!.latitude,
          _currentPosition!.longitude,
          b.latitude,
          b.longitude,
        );
        return distA.compareTo(distB);
      });
    }

    print('Creating tour: $tourName');

    // Create the tour - with retry logic for server wake-up
    final apiService = ApiService();
    Tour? newTour;
    int retries = 3;

    while (retries > 0 && newTour == null) {
      try {
        newTour = await apiService.createTour(tourName, tourDesc)
            .timeout(const Duration(seconds: 60));
        currentStep = 1;
        break;
      } catch (e) {
        print('Attempt ${4 - retries} failed: $e');
        retries--;
        if (retries > 0) {
          print('Retrying... ($retries attempts left)');
          await Future.delayed(const Duration(seconds: 3));
        } else {
          rethrow;
        }
      }
    }

    if (newTour == null) {
      throw Exception('Failed to create tour after multiple attempts');
    }

    print('Tour created with ID: ${newTour.id}');

    // For each article, create a TEXT-ONLY waypoint (no audio file generation!)
    for (int i = 0; i < articlesToSave.length; i++) {
      final article = articlesToSave[i];
      print('Processing article ${i + 1}/${articlesToSave.length}: ${article.title}');

      // Update progress
      currentStep = i + 2;

      try {
        // Get text content for the waypoint
        String textContent = article.extract;

        // Try to get full article if extract is too short
        if (textContent.length < 200) {
          try {
            final fullText = await _wikiService.getFullArticle(article.pageId);
            if (fullText.isNotEmpty) {
              textContent = fullText;
            }
          } catch (e) {
            print('Could not fetch full article, using extract: $e');
          }
        }

        // Limit text length to avoid database issues
        if (textContent.length > 2000) {
          textContent = '${textContent.substring(0, 2000)}...';
        }

        // Create introduction text
        final introduction = 'Now approaching ${article.title}. $textContent';

        // Create waypoint with TEXT ONLY (no audio file!)
        await apiService.createWaypointWithText(
          tourId: newTour.id,
          name: article.title,
          latitude: article.latitude,
          longitude: article.longitude,
          text: introduction,
        );

        print('Text waypoint created successfully for ${article.title}');
      } catch (e) {
        print('Error creating waypoint for ${article.title}: $e');
        // Continue with next article instead of failing completely
      }
    }

    if (!mounted) return;
    Navigator.pop(context); // Close loading dialog

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Tour "$tourName" saved with ${articlesToSave.length} waypoints!'),
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
    print('Error saving tour: $e');
    print('Stack trace: $stackTrace');

    if (!mounted) return;
    Navigator.pop(context); // Close loading dialog

    String errorMessage = 'Failed to save tour: $e';
    if (e.toString().contains('Connection closed') ||
        e.toString().contains('TimeoutException')) {
      errorMessage = 'Server connection timeout. The server may be starting up. Please try again in a minute.';
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
            _saveAsCustomTour();
          },
        ),
      ),
    );
  }
}


  @override
  void dispose() {
    _isDisposed = true;
    _positionStreamSubscription?.cancel();
    _positionStreamSubscription = null;
    try {
      _tts.stop();
    } catch (e) {
      print('Error stopping TTS: $e');
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Flexible(
              child: Text(
                'Wikipedia Tour',
                overflow: TextOverflow.ellipsis,
            ),
          ),
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
              _safeSetState(() {
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
              if (_currentPosition != null) {
                _searchNearbyArticles(_currentPosition!);
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 100, child: Text('100m radius')),
              const PopupMenuItem(value: 250, child: Text('250m radius')),
              const PopupMenuItem(value: 500, child: Text('500m radius')),
              const PopupMenuItem(value: 1000, child: Text('1km radius')),
              const PopupMenuItem(value: 2000, child: Text('2km radius')),
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
          initialCameraPosition: const CameraPosition(
            target: LatLng(37.7749, -122.4194),
            zoom: 15,
          ),
          onMapCreated: (controller) {
            _mapController.complete(controller);
          },
          markers: _markers,
          myLocationEnabled: true,
          myLocationButtonEnabled: true,
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
    if (_currentPosition != null) {
      sortedArticles.sort((a, b) {
        final distA = Geolocator.distanceBetween(
          _currentPosition!.latitude,
          _currentPosition!.longitude,
          a.latitude,
          a.longitude,
        );
        final distB = Geolocator.distanceBetween(
          _currentPosition!.latitude,
          _currentPosition!.longitude,
          b.latitude,
          b.longitude,
        );
        return distA.compareTo(distB);
      });
    }

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
                    ],
                  ),
              ],
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: sortedArticles.length,
            itemBuilder: (context, index) {
              final article = sortedArticles[index];
              final isCurrent = _currentArticle?.pageId == article.pageId;
              final isPlayed = _playedArticleIds.contains(article.pageId);
              final isDisabled = _disabledArticleIds.contains(article.pageId);

              double? distance;
              if (_currentPosition != null) {
                distance = Geolocator.distanceBetween(
                  _currentPosition!.latitude,
                  _currentPosition!.longitude,
                  article.latitude,
                  article.longitude,
                );
              }

              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                color: isCurrent ? Colors.green.shade50 : null,
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
                              : Icons.location_on,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                  title: Text(
                    article.title,
                    style: TextStyle(
                      fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                      decoration: isDisabled ? TextDecoration.lineThrough : null,
                      color: isDisabled ? Colors.grey : null,
                    ),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (distance != null)
                        Text(
                          distance < 1000
                              ? '${distance.toStringAsFixed(0)}m away'
                              : '${(distance / 1000).toStringAsFixed(1)}km away',
                          style: TextStyle(
                            fontSize: 12,
                            color: distance < 50 ? Colors.orange : Colors.grey,
                            fontWeight: distance < 50 ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                      if (isPlayed)
                        const Text(
                          'Already played',
                          style: TextStyle(fontSize: 11, color: Colors.purple),
                        ),
                      if (isDisabled)
                        const Text(
                          'Disabled - will not auto-play',
                          style: TextStyle(fontSize: 11, color: Colors.orange),
                        ),
                    ],
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: Icon(
                          isDisabled ? Icons.visibility_off : Icons.visibility,
                          color: isDisabled ? Colors.grey : Colors.blue,
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
                      IconButton(
                        icon: const Icon(Icons.play_arrow, color: Colors.green),
                        onPressed: () => _playArticle(article),
                      ),
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
}
