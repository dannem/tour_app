// File: lib/storage_settings_screen.dart
// Screen for users to select storage preferences

import 'package:flutter/material.dart';
import 'storage_preferences.dart';

class StorageSettingsScreen extends StatefulWidget {
  const StorageSettingsScreen({super.key});

  @override
  State<StorageSettingsScreen> createState() => _StorageSettingsScreenState();
}

class _StorageSettingsScreenState extends State<StorageSettingsScreen> {
  StorageMode _currentMode = StorageMode.server;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadCurrentMode();
  }

  Future<void> _loadCurrentMode() async {
    final mode = await StoragePreferences.getStorageMode();
    setState(() {
      _currentMode = mode;
      _isLoading = false;
    });
  }

  Future<void> _updateMode(StorageMode newMode) async {
    setState(() {
      _isLoading = true;
    });

    await StoragePreferences.setStorageMode(newMode);

    setState(() {
      _currentMode = newMode;
      _isLoading = false;
    });

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Storage mode changed to ${newMode == StorageMode.local ? "LOCAL" : "SERVER"}',
        ),
        backgroundColor: Colors.green,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Storage Settings'),
        backgroundColor: Colors.deepPurple,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Choose How to Store Your Tours',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Select where you want to save and play your tours from:',
                    style: TextStyle(fontSize: 14, color: Colors.grey),
                  ),
                  const SizedBox(height: 24),

                  // Local Storage Option
                  _buildStorageCard(
                    mode: StorageMode.local,
                    title: '📱 Local Storage',
                    subtitle: 'Save tours on this device',
                    description:
                        '• Tours stay on your phone\n'
                        '• No internet required to play\n'
                        '• Tours are private to you\n'
                        '• Cannot share with others\n'
                        '• Faster saving and loading',
                    icon: Icons.phone_android,
                    color: Colors.blue,
                  ),

                  const SizedBox(height: 16),

                  // Server Storage Option
                  _buildStorageCard(
                    mode: StorageMode.server,
                    title: '☁️ Server Storage',
                    subtitle: 'Upload tours to the cloud',
                    description:
                        '• Tours stored in the cloud\n'
                        '• Access from any device\n'
                        '• Share tours with others\n'
                        '• Requires internet connection\n'
                        '• Backup and sync enabled',
                    icon: Icons.cloud_upload,
                    color: Colors.orange,
                  ),

                  const SizedBox(height: 24),

                  // Current selection indicator
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.green.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.check_circle, color: Colors.green.shade700),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Currently using: ${_currentMode == StorageMode.local ? "Local Storage" : "Server Storage"}',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Colors.green.shade700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Info box
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blue.shade200),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.info_outline,
                          size: 20,
                          color: Colors.blue.shade700,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'You can change this setting at any time. Existing tours will remain where they were saved.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.blue.shade700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildStorageCard({
    required StorageMode mode,
    required String title,
    required String subtitle,
    required String description,
    required IconData icon,
    required Color color,
  }) {
    final isSelected = _currentMode == mode;

    return Card(
      elevation: isSelected ? 8 : 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isSelected ? color : Colors.grey.shade300,
          width: isSelected ? 3 : 1,
        ),
      ),
      child: InkWell(
        onTap: () => _updateMode(mode),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(icon, color: color, size: 32),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: isSelected ? color : Colors.black,
                          ),
                        ),
                        Text(
                          subtitle,
                          style: const TextStyle(
                            fontSize: 14,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (isSelected)
                    Icon(Icons.check_circle, color: color, size: 32),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                description,
                style: const TextStyle(fontSize: 13),
              ),
              if (isSelected)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      'ACTIVE',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
