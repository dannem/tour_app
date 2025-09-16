// File: lib/tour.dart
import 'tour_point.dart';

class Tour {
  final String name;
  final List<TourPoint> points;

  Tour({required this.name, required this.points});

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'points': points.map((point) => point.toJson()).toList(),
    };
  }

  // ADD THIS FACTORY CONSTRUCTOR
  factory Tour.fromJson(Map<String, dynamic> json) {
    var pointsList = json['points'] as List;
    List<TourPoint> tourPoints = pointsList.map((i) => TourPoint.fromJson(i)).toList();

    return Tour(
      name: json['name'],
      points: tourPoints,
    );
  }
}
