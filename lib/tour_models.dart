
class TourPoint {
  final double latitude;
  final double longitude;
  final String audioPath;

  TourPoint({
    required this.latitude,
    required this.longitude,
    required this.audioPath,
  });

  Map<String, dynamic> toJson() => {
        'latitude': latitude,
        'longitude': longitude,
        'audioPath': audioPath,
      };

  factory TourPoint.fromJson(Map<String, dynamic> json) => TourPoint(
        latitude: json['latitude'],
        longitude: json['longitude'],
        audioPath: json['audioPath'],
      );
}

class Tour {
  final String name;
  final List<TourPoint> points;

  Tour({
    required this.name,
    required this.points,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'points': points.map((point) => point.toJson()).toList(),
      };

  factory Tour.fromJson(Map<String, dynamic> json) => Tour(
        name: json['name'],
        points: List<TourPoint>.from(
            json['points'].map((point) => TourPoint.fromJson(point))),
      );
}
