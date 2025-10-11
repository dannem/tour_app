import 'dart:convert';
import 'package:http/http.dart' as http;

class WikipediaArticle {
  final String title;
  final String extract;
  final double latitude;
  final double longitude;
  final int pageId;
  final String? thumbnailUrl;

  WikipediaArticle({
    required this.title,
    required this.extract,
    required this.latitude,
    required this.longitude,
    required this.pageId,
    this.thumbnailUrl,
  });

  factory WikipediaArticle.fromJson(Map<String, dynamic> json) {
    return WikipediaArticle(
      title: json['title'] as String,
      extract: json['extract'] as String,
      latitude: (json['coordinates']?[0]?['lat'] as num?)?.toDouble() ?? 0.0,
      longitude: (json['coordinates']?[0]?['lon'] as num?)?.toDouble() ?? 0.0,
      pageId: json['pageid'] as int,
      thumbnailUrl: json['thumbnail']?['source'] as String?,
    );
  }
}

class WikipediaService {
  static const String _baseUrl = 'https://en.wikipedia.org/w/api.php';

  /// Search for Wikipedia articles near a geographic location
  Future<List<WikipediaArticle>> searchNearby({
    required double latitude,
    required double longitude,
    int radiusMeters = 1000,
    int limit = 10,
  }) async {
    final params = {
      'action': 'query',
      'format': 'json',
      'generator': 'geosearch',
      'ggscoord': '$latitude|$longitude',
      'ggsradius': radiusMeters.toString(),
      'ggslimit': limit.toString(),
      'prop': 'coordinates|extracts|pageimages',
      'exintro': '1',
      'explaintext': '1',
      'piprop': 'thumbnail',
      'pithumbsize': '300',
    };

    final uri = Uri.parse(_baseUrl).replace(queryParameters: params);

    try {
      final response = await http.get(uri);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final pages = data['query']?['pages'] as Map<String, dynamic>?;

        if (pages == null) return [];

        return pages.values
            .map((page) => WikipediaArticle.fromJson(page as Map<String, dynamic>))
            .toList();
      } else {
        throw Exception('Failed to load Wikipedia articles');
      }
    } catch (e) {
      print('Error fetching Wikipedia articles: $e');
      return [];
    }
  }

  /// Get full article content
  Future<String> getFullArticle(int pageId) async {
    final params = {
      'action': 'query',
      'format': 'json',
      'pageids': pageId.toString(),
      'prop': 'extracts',
      'explaintext': '1',
    };

    final uri = Uri.parse(_baseUrl).replace(queryParameters: params);

    try {
      final response = await http.get(uri);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final page = data['query']?['pages']?[pageId.toString()];
        return page?['extract'] as String? ?? '';
      }
    } catch (e) {
      print('Error fetching full article: $e');
    }

    return '';
  }
}
