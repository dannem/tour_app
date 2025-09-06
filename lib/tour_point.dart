// File: lib/tour_point.dart

class TourPoint {
  final double latitude;
  final double longitude;
  String? audioPath; // Make this nullable

  TourPoint({required this.latitude, required this.longitude, this.audioPath});
}
