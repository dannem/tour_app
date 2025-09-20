// File: lib/tour.dart

import 'tour_point.dart';

class Tour {
  final String name;
  final String description; // Added description to match the server model
  final int id;             // Added id to match the server model
  final List<TourPoint> waypoints;

  Tour({required this.name, required this.description, required this.id, required this.waypoints});

  // The fromJson method is the one that was causing the error
  factory Tour.fromJson(Map<String, dynamic> json) {
    // This line now correctly looks for 'waypoints' instead of 'points'
    var pointsList = json['waypoints'] as List;
    List<TourPoint> tourPoints = pointsList.map((i) => TourPoint.fromJson(i)).toList();

    return Tour(
      name: json['name'],
      description: json['description'],
      id: json['id'],
      waypoints: tourPoints,
    );
  }

  // Note: The toJson method is no longer needed in the app for now,
  // as we will be creating tours via HTTP requests.
}
