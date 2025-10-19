import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'wikipedia_playback_screen.dart';

class WikipediaLocationSelector extends StatefulWidget {
  const WikipediaLocationSelector({super.key});

  @override
  State<WikipediaLocationSelector> createState() => _WikipediaLocationSelectorState();
}

class _WikipediaLocationSelectorState extends State<WikipediaLocationSelector> {
  LocationSelectionMethod _selectedMethod = LocationSelectionMethod.currentLocation;
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _latController = TextEditingController();
  final TextEditingController _lonController = TextEditingController();

  Position? _currentPosition;
  Position? _selectedPosition;
  bool _isLoadingLocation = false;
  String _statusMessage = '';

  @override
  void initState() {
    super.initState();
    _getCurrentLocation();
  }

  @override
  void dispose() {
    _addressController.dispose();
    _latController.dispose();
    _lonController.dispose();
    super.dispose();
  }

  Future<void> _getCurrentLocation() async {
    setState(() {
      _isLoadingLocation = true;
      _statusMessage = 'Getting current location...';
    });

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() {
          _statusMessage = 'Location services are disabled.';
          _isLoadingLocation = false;
        });
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          setState(() {
            _statusMessage = 'Location permissions denied.';
            _isLoadingLocation = false;
          });
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        setState(() {
          _statusMessage = 'Location permissions permanently denied.';
          _isLoadingLocation = false;
        });
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      setState(() {
        _currentPosition = position;
        _selectedPosition = position;
        _statusMessage = 'Current location found';
        _isLoadingLocation = false;
      });
    } catch (e) {
      setState(() {
        _statusMessage = 'Error getting location: $e';
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
      _isLoadingLocation = true;
      _statusMessage = 'Finding address...';
    });

    try {
      final locations = await locationFromAddress(_addressController.text);
      if (locations.isNotEmpty) {
        final location = locations.first;
        setState(() {
          _selectedPosition = Position(
            latitude: location.latitude,
            longitude: location.longitude,
            timestamp: DateTime.now(),
            accuracy: 0,
            altitude: 0,
            heading: 0,
            speed: 0,
            speedAccuracy: 0,
            headingAccuracy: 0,
            altitudeAccuracy: 0,
          );
          _statusMessage = 'Address found';
          _isLoadingLocation = false;
        });
      } else {
        setState(() {
          _statusMessage = 'Address not found';
          _isLoadingLocation = false;
        });
      }
    } catch (e) {
      setState(() {
        _statusMessage = 'Error finding address: $e';
        _isLoadingLocation = false;
      });
    }
  }

  void _validateAndSetManualCoordinates() async {
    final lat = double.tryParse(_latController.text);
    final lon = double.tryParse(_lonController.text);

    if (lat == null || lon == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter valid coordinates')),
      );
      return;
    }

    if (lat < -90 || lat > 90 || lon < -180 || lon > 180) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Coordinates out of valid range')),
      );
      return;
    }

    setState(() {
      _selectedPosition = Position(
        latitude: lat,
        longitude: lon,
        timestamp: DateTime.now(),
        accuracy: 0,
        altitude: 0,
        heading: 0,
        speed: 0,
        speedAccuracy: 0,
        headingAccuracy: 0,
        altitudeAccuracy: 0,
      );
      _statusMessage = 'Manual coordinates set';
    });
  }

  void _openMapSelector() async {
    final result = await Navigator.push<Position>(
      context,
      MaterialPageRoute(
        builder: (context) => MapLocationPicker(
          initialPosition: _selectedPosition ?? _currentPosition,
        ),
      ),
    );

    if (result != null) {
      setState(() {
        _selectedPosition = result;
        _statusMessage = 'Location selected from map';
      });
    }
  }

  void _startWikipediaTour() {
    if (_selectedPosition == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a location first')),
      );
      return;
    }

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => WikipediaPlaybackScreen(
          initialPosition: _selectedPosition,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Choose Location for Wikipedia Tour'),
        backgroundColor: Colors.orange,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Select where you want to find Wikipedia articles:',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (_statusMessage.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            if (_isLoadingLocation)
                              const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            else
                              const Icon(Icons.info_outline, size: 16, color: Colors.blue),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _statusMessage,
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (_selectedPosition != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.green.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.green),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              '✓ Location Selected:',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.green,
                              ),
                            ),
                            Text(
                              'Lat: ${_selectedPosition!.latitude.toStringAsFixed(6)}',
                              style: const TextStyle(fontSize: 12),
                            ),
                            Text(
                              'Lon: ${_selectedPosition!.longitude.toStringAsFixed(6)}',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Current Location Option
            _buildMethodCard(
              method: LocationSelectionMethod.currentLocation,
              icon: Icons.my_location,
              title: 'Current Location',
              subtitle: 'Use my current GPS position',
              child: ElevatedButton.icon(
                icon: const Icon(Icons.gps_fixed),
                label: const Text('Use Current Location'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                ),
                onPressed: _isLoadingLocation ? null : _getCurrentLocation,
              ),
            ),

            // Address Search Option
            _buildMethodCard(
              method: LocationSelectionMethod.address,
              icon: Icons.location_on,
              title: 'Search by Address',
              subtitle: 'Enter a city, place, or address',
              child: Column(
                children: [
                  TextField(
                    controller: _addressController,
                    decoration: const InputDecoration(
                      labelText: 'Enter address',
                      hintText: 'e.g., Eiffel Tower, Paris',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.search),
                    ),
                    onSubmitted: (_) => _geocodeAddress(),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.search),
                      label: const Text('Find Location'),
                      onPressed: _geocodeAddress,
                    ),
                  ),
                ],
              ),
            ),

            // Map Selection Option
            _buildMethodCard(
              method: LocationSelectionMethod.map,
              icon: Icons.map,
              title: 'Pick from Map',
              subtitle: 'Tap on a map to select location',
              child: ElevatedButton.icon(
                icon: const Icon(Icons.map),
                label: const Text('Open Map'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                ),
                onPressed: _openMapSelector,
              ),
            ),

            // Manual Coordinates Option
            _buildMethodCard(
              method: LocationSelectionMethod.manual,
              icon: Icons.edit_location,
              title: 'Manual Coordinates',
              subtitle: 'Enter exact latitude and longitude',
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _latController,
                          decoration: const InputDecoration(
                            labelText: 'Latitude',
                            hintText: 'e.g., 48.8584',
                            border: OutlineInputBorder(),
                          ),
                          keyboardType: const TextInputType.numberWithOptions(
                            signed: true,
                            decimal: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _lonController,
                          decoration: const InputDecoration(
                            labelText: 'Longitude',
                            hintText: 'e.g., 2.2945',
                            border: OutlineInputBorder(),
                          ),
                          keyboardType: const TextInputType.numberWithOptions(
                            signed: true,
                            decimal: true,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.check),
                      label: const Text('Set Coordinates'),
                      onPressed: _validateAndSetManualCoordinates,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Start Tour Button
            SizedBox(
              height: 56,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.play_arrow, size: 28),
                label: const Text(
                  'Start Wikipedia Tour',
                  style: TextStyle(fontSize: 18),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                  elevation: 4,
                ),
                onPressed: _selectedPosition == null ? null : _startWikipediaTour,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMethodCard({
    required LocationSelectionMethod method,
    required IconData icon,
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    final bool isSelected = _selectedMethod == method;

    return Card(
      elevation: isSelected ? 4 : 1,
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isSelected ? Colors.orange : Colors.transparent,
          width: 2,
        ),
      ),
      child: InkWell(
        onTap: () {
          setState(() {
            _selectedMethod = method;
          });
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: isSelected ? Colors.orange.shade50 : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      icon,
                      color: isSelected ? Colors.orange : Colors.grey,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: isSelected ? Colors.orange : Colors.black,
                          ),
                        ),
                        Text(
                          subtitle,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Radio<LocationSelectionMethod>(
                    value: method,
                    groupValue: _selectedMethod,
                    onChanged: (value) {
                      if (value != null) {
                        setState(() {
                          _selectedMethod = value;
                        });
                      }
                    },
                    activeColor: Colors.orange,
                  ),
                ],
              ),
              if (isSelected) ...[
                const SizedBox(height: 16),
                child,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

enum LocationSelectionMethod {
  currentLocation,
  address,
  map,
  manual,
}

// Map Location Picker Screen
class MapLocationPicker extends StatefulWidget {
  final Position? initialPosition;

  const MapLocationPicker({super.key, this.initialPosition});

  @override
  State<MapLocationPicker> createState() => _MapLocationPickerState();
}

class _MapLocationPickerState extends State<MapLocationPicker> {
  final Completer<GoogleMapController> _mapController = Completer();
  Position? _selectedPosition;
  LatLng? _selectedLatLng;
  Set<Marker> _markers = {};

  @override
  void initState() {
    super.initState();
    if (widget.initialPosition != null) {
      _selectedPosition = widget.initialPosition;
      _selectedLatLng = LatLng(
        widget.initialPosition!.latitude,
        widget.initialPosition!.longitude,
      );
      _updateMarker(_selectedLatLng!);
    }
  }

  void _updateMarker(LatLng position) {
    setState(() {
      _markers = {
        Marker(
          markerId: const MarkerId('selected'),
          position: position,
          draggable: true,
          onDragEnd: (newPosition) {
            _onMapTap(newPosition);
          },
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
        ),
      };
    });
  }

  void _onMapTap(LatLng position) {
    setState(() {
      _selectedLatLng = position;
      _selectedPosition = Position(
        latitude: position.latitude,
        longitude: position.longitude,
        timestamp: DateTime.now(),
        accuracy: 0,
        altitude: 0,
        heading: 0,
        speed: 0,
        speedAccuracy: 0,
        headingAccuracy: 0,
        altitudeAccuracy: 0,
      );
      _updateMarker(position);
    });
  }

  void _confirmSelection() {
    if (_selectedPosition != null) {
      Navigator.pop(context, _selectedPosition);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Select Location'),
        backgroundColor: Colors.orange,
        actions: [
          IconButton(
            icon: const Icon(Icons.check),
            onPressed: _selectedPosition != null ? _confirmSelection : null,
            tooltip: 'Confirm Location',
          ),
        ],
      ),
      body: Stack(
        children: [
          GoogleMap(
            onMapCreated: (controller) => _mapController.complete(controller),
            initialCameraPosition: CameraPosition(
              target: _selectedLatLng ?? const LatLng(37.7749, -122.4194),
              zoom: 15,
            ),
            markers: _markers,
            onTap: _onMapTap,
            myLocationEnabled: true,
            myLocationButtonEnabled: true,
          ),
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
                    const Text(
                      'Tap on the map to select a location',
                      style: TextStyle(fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                    if (_selectedPosition != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Lat: ${_selectedPosition!.latitude.toStringAsFixed(6)}, Lon: ${_selectedPosition!.longitude.toStringAsFixed(6)}',
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.check_circle),
                          label: const Text('Confirm This Location'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          onPressed: _confirmSelection,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
