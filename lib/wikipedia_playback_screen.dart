import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'wikipedia_service.dart';

class WikipediaPlaybackScreen extends StatefulWidget {
  const WikipediaPlaybackScreen({super.key});

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
  Position? _currentPosition;
  final Set<int> _playedArticleIds = {};
  final Set<int> _disabledArticleIds = {}; // Articles user has disabled
  bool _showListView = false; // Toggle between map and list view

  @override
  void initState() {
    super.initState();
    _initializeTts();
    _startLocationListener();
  }

  Future<void> _initializeTts() async {
    await _tts.setLanguage("en-US");
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

  Future<void> _startLocationListener() async {
    await _determinePosition();

    _positionStreamSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 20,
      ),
    ).listen((Position position) async {
      setState(() {
        _currentPosition = position;
      });

      // Update camera to follow user
      final controller = await _mapController.future;
      controller.animateCamera(
        CameraUpdate.newLatLng(LatLng(position.latitude, position.longitude)),
      );

      // Search for nearby Wikipedia articles
      await _searchNearbyArticles(position);

      // Check if user is near any article
      if (!_isPlaying) {
        _checkProximityToArticles(position);
      }
    });
  }

  Future<void> _searchNearbyArticles(Position position) async {
    try {
      final articles = await _wikiService.searchNearby(
        latitude: position.latitude,
        longitude: position.longitude,
        radiusMeters: _searchRadiusMeters,
        limit: 20,
      );

      setState(() {
        _nearbyArticles = articles;
        _updateMarkers();
        if (!_isPlaying && articles.isNotEmpty) {
          _statusMessage = 'Found ${articles.length} nearby places';
        }
      });
    } catch (e) {
      print('Error searching Wikipedia: $e');
    }
  }

  void _updateMarkers() {
    _markers = _nearbyArticles.map((article) {
      final isPlayed = _playedArticleIds.contains(article.pageId);
      final isCurrent = _currentArticle?.pageId == article.pageId;
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
      // Skip if already played or disabled by user
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

      // Trigger when within 50 meters
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

    // Get full article if extract is too short
    String textToRead = article.extract;
    if (textToRead.length < 200) {
      textToRead = await _wikiService.getFullArticle(article.pageId);
    }

    // Add introduction
    final introduction = 'Now approaching ${article.title}. ${textToRead}';
    await _tts.speak(introduction);
  }

  Future<void> _pauseResume() async {
    if (_isPaused) {
      await _tts.speak(''); // Resume
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
              Row(
                children: [
                  Expanded(
                    child: Text(
                      article.title,
                      style: const TextStyle(
                        fontSize: 24,
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
              if (article.thumbnailUrl != null)
                Image.network(
                  article.thumbnailUrl!,
                  height: 150,
                  fit: BoxFit.cover,
                ),
              const SizedBox(height: 16),
              Expanded(
                child: SingleChildScrollView(
                  controller: scrollController,
                  child: Text(article.extract),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Play This Article'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onPressed: () {
                    Navigator.pop(context);
                    _playArticle(article);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _positionStreamSubscription?.cancel();
    _tts.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Wikipedia Tour'),
        actions: [
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
              if (_currentPosition != null) {
                _searchNearbyArticles(_currentPosition!);
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
                          if (_disabledArticleIds.isNotEmpty)
                            Text(
                              '${_disabledArticleIds.length} disabled',
                              style: const TextStyle(fontSize: 11, color: Colors.orange),
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
    // Sort articles by distance from current position
    final sortedArticles = List<WikipediaArticle>.from(_nearbyArticles);
    if (_currentPosition != null) {
      sortedArticles.sort((a, b) {
        final distA = Geolocator.distanceBetween(
          _currentPosition!.latitude,
          _currentPosition!.longitude,
          a.latitude,
          b.longitude,
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
        // Status card at top
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
                const SizedBox(height: 8),
                Text(
                  '${_nearbyArticles.length - _disabledArticleIds.length} of ${_nearbyArticles.length} articles enabled',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
                if (_disabledArticleIds.isNotEmpty)
                  TextButton.icon(
                    icon: const Icon(Icons.refresh, size: 16),
                    label: const Text('Enable All'),
                    onPressed: () {
                      setState(() {
                        _disabledArticleIds.clear();
                        _updateMarkers();
                      });
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('All articles enabled'),
                          duration: Duration(seconds: 1),
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),
        ),
        // List of articles
        Expanded(
          child: sortedArticles.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.search_off, size: 64, color: Colors.grey),
                      SizedBox(height: 16),
                      Text('No articles found nearby'),
                      Text(
                        'Try increasing the search radius',
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
                            // Toggle enable/disable
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
                                    // Stop if currently playing
                                    if (isCurrent) {
                                      _stopPlayback();
                                    }
                                  }
                                  _updateMarkers();
                                });

                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      isDisabled
                                          ? '"${article.title}" enabled'
                                          : '"${article.title}" disabled',
                                    ),
                                    duration: const Duration(seconds: 1),
                                  ),
                                );
                              },
                              tooltip: isDisabled ? 'Enable' : 'Disable',
                            ),
                            // Play button
                            IconButton(
                              icon: Icon(
                                isCurrent && _isPlaying ? Icons.stop : Icons.play_arrow,
                                color: isDisabled ? Colors.grey : Colors.green,
                              ),
                              onPressed: isDisabled
                                  ? null
                                  : () {
                                      if (isCurrent && _isPlaying) {
                                        _stopPlayback();
                                      } else {
                                        _playArticle(article);
                                      }
                                    },
                              tooltip: isCurrent && _isPlaying ? 'Stop' : 'Play',
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
  }
}
