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
}
