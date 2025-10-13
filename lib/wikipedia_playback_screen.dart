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
  int _audioFileCounter = 0;

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
                        ? const Icon(Icons.check_circle, color: Colors.blue)
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

      final controller = await _mapController.future;
      controller.animateCamera(
        CameraUpdate.newLatLng(LatLng(position.latitude, position.longitude)),
      );

      await _searchNearbyArticles(position);

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
        } else if (articles.isEmpty) {
          _statusMessage = 'No articles found in ${_currentLanguage.nativeName}. Try another language or increase radius.';
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

  Future<String?> _generateAudio(String text, String title) async {
    try {
      print('=== Generating TTS for: $title ===');
      print('Extract length: ${text.length}');

      // Truncate text if too long
      if (text.length > 1000) {
        text = text.substring(0, 1000);
        print('Text truncated to 1000 characters');
      }

      // Add title at the beginning
      String fullText = "$title. $text";
      print('Final text length: ${fullText.length}');

      // Get external storage directory
      final directory = await getExternalStorageDirectory();
      if (directory == null) {
        print('ERROR: Could not get external storage directory');
        return null;
      }

      // Create unique filename with timestamp
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final filename = 'wiki_tts_${timestamp}_${_audioFileCounter++}.wav';
      final filepath = '${directory.path}/$filename';

      print('Attempting to generate TTS audio at: $filepath');

      // Create a completer to wait for TTS completion
      final completer = Completer<String?>();
      String? completedFilePath;

      // Set up completion handler BEFORE starting synthesis
      _tts.setCompletionHandler(() {
        print('TTS completion handler called');
        if (!completer.isCompleted) {
          completer.complete(completedFilePath);
        }
      });

      // Synthesize to file
      final result = await _tts.synthesizeToFile(fullText, filepath);
      print('TTS synthesizeToFile result: $result');

      if (result == 1) {
        print('TTS synthesis started successfully');

        // Wait for completion with timeout
        try {
          await completer.future.timeout(
            Duration(seconds: 30),
            onTimeout: () {
              print('WARNING: TTS completion timeout after 30 seconds');
              return null;
            },
          );

          // Give it a moment for file system to sync
          await Future.delayed(Duration(milliseconds: 500));

          // Search for the file in multiple possible locations
          print('Searching for generated audio file...');

          // Method 1: Check original path
          File file = File(filepath);
          if (await file.exists()) {
            final fileSize = await file.length();
            print('✅ Found at original path: $filepath (${fileSize} bytes)');
            return filepath;
          }

          // Method 2: Search in directory
          print('Not at original path, searching directory...');
          final files = directory.listSync(recursive: false);
          for (var f in files) {
            if (f is File && f.path.contains(filename)) {
              final fileSize = await f.length();
              print('✅ Found in directory: ${f.path} (${fileSize} bytes)');
              return f.path;
            }
          }

          // Method 3: Search for any recent wiki_tts file
          print('Searching for any recent TTS files...');
          final recentFiles = files.where((f) =>
            f is File &&
            f.path.contains('wiki_tts') &&
            f.path.endsWith('.wav')
          ).toList();

          if (recentFiles.isNotEmpty) {
            // Sort by modification time and get the most recent
            recentFiles.sort((a, b) =>
              (b as File).lastModifiedSync().compareTo((a as File).lastModifiedSync())
            );
            final mostRecent = recentFiles.first as File;
            final fileSize = await mostRecent.length();
            print('✅ Found recent file: ${mostRecent.path} (${fileSize} bytes)');
            return mostRecent.path;
          }

          print('ERROR: Could not find generated audio file anywhere');
          return null;

        } catch (e) {
          print('ERROR waiting for TTS completion: $e');
          return null;
        }
      } else {
        print('ERROR: TTS synthesis failed with result: $result');
        return null;
      }
    } catch (e, stackTrace) {
      print('ERROR generating audio: $e');
      print('Stack trace: $stackTrace');
      return null;
    }
  }

  @override
  void dispose() {
    _positionStreamSubscription?.cancel();
    _tts.stop();
    super.dispose();
  }

  void _saveAsCustomTour() async {
    if (_nearbyArticles.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No articles to save. Search for nearby places first.'),
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

    // Show dialog to get tour name and description
    final nameController = TextEditingController(
      text: 'Wikipedia Tour - ${_currentLanguage.nativeName}',
    );
    final descController = TextEditingController(
      text: 'Wikipedia articles in ${_currentLanguage.nativeName} near ${_currentPosition?.latitude.toStringAsFixed(4)}, ${_currentPosition?.longitude.toStringAsFixed(4)}',
    );

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
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.info_outline, size: 16, color: Colors.blue),
                        SizedBox(width: 4),
                        Text(
                          'How it works:',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                        ),
                      ],
                    ),
                    SizedBox(height: 4),
                    Text(
                      '• Audio will be generated during playback\n'
                      '• Articles are saved in order of distance\n'
                      '• You can play this tour later from the main menu',
                      style: TextStyle(fontSize: 11),
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
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
            child: const Text('Save Tour'),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      if (mounted) {
        nameController.dispose();
        descController.dispose();
      }
      return;
    }

    final tourName = nameController.text;
    final tourDesc = descController.text;

    // Dispose controllers after getting the text
    if (mounted) {
      nameController.dispose();
      descController.dispose();
    }

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
                        ? 'Saving waypoint $currentStep/${articlesToSave.length}...'
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

      // Track successful waypoints
      int successfulWaypoints = 0;
      List<String> failedArticles = [];

      // For each article, create a waypoint WITHOUT audio (audio will be generated on-the-fly during playback)
      for (int i = 0; i < articlesToSave.length; i++) {
        final article = articlesToSave[i];
        print('Processing article ${i + 1}/${articlesToSave.length}: ${article.title}');

        // Update progress
        currentStep = i + 2;

        try {
          // Create waypoint with article data - no audio file needed
          // Store the full text in the waypoint description for TTS playback later
          String description = article.extract;

          // If extract is short, try to get full article
          if (description.length < 200) {
            try {
              final fullText = await _wikiService.getFullArticle(article.pageId);
              if (fullText.isNotEmpty) {
                description = fullText;
              }
            } catch (e) {
              print('Using extract for ${article.title}: $e');
            }
          }

          // Limit text length
          if (description.length > 1000) {
            description = description.substring(0, 1000);
          }

          print('Creating waypoint on server...');
          await apiService.createWaypoint(
            tourId: newTour.id,
            name: article.title,
            latitude: article.latitude,
            longitude: article.longitude,
            description: description, // Store text for TTS generation during playback
            audioFilePath: null, // No pre-generated audio
          );

          successfulWaypoints++;
          print('✅ Waypoint ${successfulWaypoints} created successfully');
        } catch (e) {
          print('❌ Error creating waypoint for ${article.title}: $e');
          failedArticles.add(article.title);
          // Continue with next article instead of failing completely
        }
      }

      if (!mounted) return;
      Navigator.pop(context); // Close loading dialog

      print('=== SUMMARY ===');
      print('Total articles: ${articlesToSave.length}');
      print('Successful waypoints: $successfulWaypoints');
      print('Failed articles: ${failedArticles.length}');
      if (failedArticles.isNotEmpty) {
        print('Failed: ${failedArticles.join(", ")}');
      }

      if (successfulWaypoints == 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to create any waypoints.'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
            action: SnackBarAction(
              label: 'Details',
              textColor: Colors.white,
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Waypoint Creation Failed'),
                    content: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('No waypoints were created. Check your internet connection and server status.'),
                          const SizedBox(height: 16),
                          const Text('Possible causes:', style: TextStyle(fontWeight: FontWeight.bold)),
                          const Text('• Server connection issues'),
                          const Text('• Network timeout'),
                          const Text('• Invalid data format'),
                          if (failedArticles.isNotEmpty) ...[
                            const SizedBox(height: 16),
                            const Text('Failed articles:', style: TextStyle(fontWeight: FontWeight.bold)),
                            Text(failedArticles.join('\n'), style: const TextStyle(fontSize: 12)),
                          ],
                        ],
                      ),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('OK'),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        );
      } else if (failedArticles.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Tour saved with $successfulWaypoints waypoints! ${failedArticles.length} failed.'),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 4),
            action: SnackBarAction(
              label: 'View',
              textColor: Colors.white,
              onPressed: () {
                Navigator.pop(context); // Go back to main menu
              },
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Tour "$tourName" saved with $successfulWaypoints waypoints!'),
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
      }
    } catch (e, stackTrace) {
      print('Error saving tour: $e');
      print('Stack trace: $stackTrace');

      if (!mounted) return;
      Navigator.pop(context); // Close loading dialog

      String errorMessage = 'Failed to save tour: $e';
      String errorDetail = '';

      if (e.toString().contains('SocketException') ||
          e.toString().contains('Failed host lookup')) {
        errorMessage = 'Cannot connect to server';
        errorDetail = 'The server may be offline or your internet connection may be down. Please check your connection and try again.';
      } else if (e.toString().contains('Connection closed') ||
          e.toString().contains('TimeoutException')) {
        errorMessage = 'Server connection timeout';
        errorDetail = 'The server may be starting up. Please wait a minute and try again.';
      } else if (e.toString().contains('HandshakeException') ||
          e.toString().contains('CERTIFICATE_VERIFY_FAILED')) {
        errorMessage = 'SSL Certificate Error';
        errorDetail = 'There is an issue with the server\'s security certificate.';
      }

      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(errorMessage),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (errorDetail.isNotEmpty) ...[
                Text(errorDetail),
                const SizedBox(height: 16),
              ],
              const Text(
                'Troubleshooting:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                '1. Check your internet connection\n'
                '2. Visit the server URL in a browser to wake it up\n'
                '3. Wait 1-2 minutes and retry\n'
                '4. Switch between WiFi and mobile data',
                style: TextStyle(fontSize: 12),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                _saveAsCustomTour();
              },
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }
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
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.3),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                _currentLanguage.code.toUpperCase(),
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
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
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${_nearbyArticles.length - _disabledArticleIds.length} of ${_nearbyArticles.length} articles enabled',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    TextButton.icon(
                      icon: const Icon(Icons.language, size: 16),
                      label: Text(_currentLanguage.nativeName),
                      onPressed: _showLanguageSelector,
                    ),
                  ],
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
        Expanded(
          child: sortedArticles.isEmpty
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
