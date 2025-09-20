// File: lib/tour_point.dart

class TourPoint {
  final double latitude;
  final double longitude;
  final int? id; // Changed to optional (nullable)
  final int? tour_id; // Changed to optional (nullable)
  String? audioPath;
  final String? audio_filename;

  TourPoint({
    required this.latitude,
    required this.longitude,
    this.id, // No longer required
    this.tour_id, // No longer required
    this.audioPath,
    this.audio_filename,
  });

  factory TourPoint.fromJson(Map<String, dynamic> json) {
    return TourPoint(
      latitude: json['latitude'],
      longitude: json['longitude'],
      id: json['id'],
      tour_id: json['tour_id'],
      audio_filename: json['audio_filename'],
    );
  }
}
