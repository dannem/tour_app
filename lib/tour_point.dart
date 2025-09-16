// File: lib/tour_point.dart

class TourPoint {
  final double latitude;
  final double longitude;
  String? audioPath;

  TourPoint({required this.latitude, required this.longitude, this.audioPath});

  // ADD THIS METHOD
  Map<String, dynamic> toJson() {
    return {
      'latitude': latitude,
      'longitude': longitude,
      'audioPath': audioPath,
    };
  }
  factory TourPoint.fromJson(Map<String, dynamic> json) {
    return TourPoint(
      latitude: json['latitude'],
      longitude: json['longitude'],
      audioPath: json['audioPath'],
    );
  }
}
