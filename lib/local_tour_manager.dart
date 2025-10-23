// File: lib/local_tour_manager.dart
// Manages local storage of tours on the device

import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'main.dart';

class LocalTourManager {
  // Get the directory for storing tours locally
  Future<Directory> get _localToursDirectory async {
    final appDir = await getApplicationDocumentsDirectory();
    final toursDir = Directory('${appDir.path}/local_tours');
    if (!await toursDir.exists()) {
      await toursDir.create(recursive: true);
    }
    return toursDir;
  }

  // Get the directory for storing audio files
  Future<Directory> get _audioDirectory async {
    final appDir = await getApplicationDocumentsDirectory();
    final audioDir = Directory('${appDir.path}/audio_files');
    if (!await audioDir.exists()) {
      await audioDir.create(recursive: true);
    }
    return audioDir;
  }

  // Save a tour locally
  Future<LocalTour> saveTour({
    required String name,
    required String description,
    required List<TourPoint> waypoints,
  }) async {
    try {
      final toursDir = await _localToursDirectory;

      // Generate a unique ID based on timestamp
      final id = DateTime.now().millisecondsSinceEpoch;

      // Create tour JSON
      final tourData = {
        'id': id,
        'name': name,
        'description': description,
        'created_at': DateTime.now().toIso8601String(),
        'waypoints': waypoints.map((wp) => {
          'id': wp.id,
          'latitude': wp.latitude,
          'longitude': wp.longitude,
          'audio_filename': wp.audioFilePath,
          'local_audio_path': wp.localAudioPath,
          'name': wp.name,
          'text': wp.text,
        }).toList(),
      };

      // Save tour metadata
      final tourFile = File('${toursDir.path}/tour_$id.json');
      await tourFile.writeAsString(json.encode(tourData));

      print('✅ Tour saved locally: $name (ID: $id)');

      return LocalTour(
        id: id,
        name: name,
        description: description,
        waypoints: waypoints,
        createdAt: DateTime.now(),
      );
    } catch (e) {
      print('❌ Error saving tour locally: $e');
      rethrow;
    }
  }

  // Load all local tours
  Future<List<LocalTour>> loadAllTours() async {
    try {
      final toursDir = await _localToursDirectory;
      final tourFiles = toursDir
          .listSync()
          .where((item) => item is File && item.path.endsWith('.json'))
          .cast<File>()
          .toList();

      final tours = <LocalTour>[];
      for (final file in tourFiles) {
        try {
          final content = await file.readAsString();
          final tourData = json.decode(content) as Map<String, dynamic>;

          final waypoints = (tourData['waypoints'] as List).map((wp) {
            return TourPoint(
              id: wp['id'] as int? ?? 0,
              latitude: (wp['latitude'] as num).toDouble(),
              longitude: (wp['longitude'] as num).toDouble(),
              audioFilePath: wp['audio_filename'] as String? ?? '',
              localAudioPath: wp['local_audio_path'] as String?,
              name: wp['name'] as String?,
              text: wp['text'] as String?,
            );
          }).toList();

          tours.add(LocalTour(
            id: tourData['id'] as int,
            name: tourData['name'] as String,
            description: tourData['description'] as String? ?? '',
            waypoints: waypoints,
            createdAt: DateTime.parse(tourData['created_at'] as String),
          ));
        } catch (e) {
          print('⚠️  Error loading tour from ${file.path}: $e');
        }
      }

      tours.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      print('✅ Loaded ${tours.length} local tours');
      return tours;
    } catch (e) {
      print('❌ Error loading local tours: $e');
      return [];
    }
  }

  // Delete a local tour
  Future<void> deleteTour(int tourId) async {
    try {
      final toursDir = await _localToursDirectory;
      final tourFile = File('${toursDir.path}/tour_$tourId.json');

      if (await tourFile.exists()) {
        await tourFile.delete();
        print('✅ Local tour deleted: $tourId');
      }
    } catch (e) {
      print('❌ Error deleting local tour: $e');
      rethrow;
    }
  }

  // Copy audio file to local storage
  Future<String> copyAudioFile(String sourcePath) async {
    try {
      final audioDir = await _audioDirectory;
      final sourceFile = File(sourcePath);
      final fileName = sourcePath.split('/').last;
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final newFileName = '${timestamp}_$fileName';
      final destPath = '${audioDir.path}/$newFileName';

      await sourceFile.copy(destPath);
      print('✅ Audio file copied to: $destPath');
      return destPath;
    } catch (e) {
      print('❌ Error copying audio file: $e');
      rethrow;
    }
  }

  // Get a specific tour by ID
  Future<LocalTour?> getTour(int tourId) async {
    try {
      final toursDir = await _localToursDirectory;
      final tourFile = File('${toursDir.path}/tour_$tourId.json');

      if (!await tourFile.exists()) {
        return null;
      }

      final content = await tourFile.readAsString();
      final tourData = json.decode(content) as Map<String, dynamic>;

      final waypoints = (tourData['waypoints'] as List).map((wp) {
        return TourPoint(
          id: wp['id'] as int? ?? 0,
          latitude: (wp['latitude'] as num).toDouble(),
          longitude: (wp['longitude'] as num).toDouble(),
          audioFilePath: wp['audio_filename'] as String? ?? '',
          localAudioPath: wp['local_audio_path'] as String?,
          name: wp['name'] as String?,
          text: wp['text'] as String?,
        );
      }).toList();

      return LocalTour(
        id: tourData['id'] as int,
        name: tourData['name'] as String,
        description: tourData['description'] as String? ?? '',
        waypoints: waypoints,
        createdAt: DateTime.parse(tourData['created_at'] as String),
      );
    } catch (e) {
      print('❌ Error loading tour $tourId: $e');
      return null;
    }
  }
}

// Local tour model
class LocalTour {
  final int id;
  final String name;
  final String description;
  final List<TourPoint> waypoints;
  final DateTime createdAt;

  LocalTour({
    required this.id,
    required this.name,
    required this.description,
    required this.waypoints,
    required this.createdAt,
  });

  // Convert to Tour object for compatibility
  Tour toTour() {
    return Tour(
      id: id,
      title: name,
      description: description,
      points: waypoints,
    );
  }
}
