// File: lib/storage_preferences.dart
// Manages user preferences for tour storage (local vs server)

import 'package:shared_preferences/shared_preferences.dart';

enum StorageMode {
  local,  // Save tours locally on the device
  server, // Upload tours to the server
}

class StoragePreferences {
  static const String _storageKey = 'tour_storage_mode';

  // Get the current storage mode
  static Future<StorageMode> getStorageMode() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final modeString = prefs.getString(_storageKey);

      if (modeString == null) {
        // Default to local mode
        return StorageMode.local;
      }

      return modeString == 'local' ? StorageMode.local : StorageMode.server;
    } catch (e) {
      print('Error getting storage mode: $e');
      return StorageMode.local; // Default fallback
    }
  }

  // Set the storage mode
  static Future<void> setStorageMode(StorageMode mode) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_storageKey, mode == StorageMode.local ? 'local' : 'server');
      print('✅ Storage mode set to: ${mode == StorageMode.local ? "LOCAL" : "SERVER"}');
    } catch (e) {
      print('❌ Error setting storage mode: $e');
      rethrow;
    }
  }

  // Clear all preferences (useful for testing)
  static Future<void> clearPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }
}
