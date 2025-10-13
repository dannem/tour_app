import 'dart:convert';
import 'package:http/http.dart' as http;

class WikipediaArticle {
  final String title;
  final String extract;
  final double latitude;
  final double longitude;
  final int pageId;
  final String? thumbnailUrl;
  final bool hasValidCoordinates;

  WikipediaArticle({
    required this.title,
    required this.extract,
    required this.latitude,
    required this.longitude,
    required this.pageId,
    this.thumbnailUrl,
    required this.hasValidCoordinates,
  });

  factory WikipediaArticle.fromJson(Map<String, dynamic> json) {
    // Extract coordinates with better validation
    double lat = 0.0;
    double lon = 0.0;
    bool validCoords = false;

    // Debug logging
    print('Parsing article: ${json['title']}');

    if (json['coordinates'] != null && json['coordinates'] is List) {
      final coordsList = json['coordinates'] as List;
      print('Coordinates list length: ${coordsList.length}');

      if (coordsList.isNotEmpty) {
        final firstCoord = coordsList[0];
        print('First coordinate: $firstCoord');

        if (firstCoord is Map<String, dynamic>) {
          if (firstCoord.containsKey('lat') && firstCoord.containsKey('lon')) {
            lat = (firstCoord['lat'] as num).toDouble();
            lon = (firstCoord['lon'] as num).toDouble();

            // Validate that coordinates are not zero or invalid
            if (lat != 0.0 && lon != 0.0 && lat.abs() <= 90 && lon.abs() <= 180) {
              validCoords = true;
              print('✅ Valid coordinates: $lat, $lon');
            } else {
              print('⚠️ Invalid coordinates: $lat, $lon');
            }
          }
        }
      }
    } else {
      print('⚠️ No coordinates field found');
    }

    return WikipediaArticle(
      title: json['title'] as String,
      extract: json['extract'] as String,
      latitude: lat,
      longitude: lon,
      pageId: json['pageid'] as int,
      thumbnailUrl: json['thumbnail']?['source'] as String?,
      hasValidCoordinates: validCoords,
    );
  }
}

class WikipediaLanguage {
  final String code;
  final String name;
  final String nativeName;

  const WikipediaLanguage({
    required this.code,
    required this.name,
    required this.nativeName,
  });

  static const List<WikipediaLanguage> languages = [
    WikipediaLanguage(code: 'en', name: 'English', nativeName: 'English'),
    WikipediaLanguage(code: 'es', name: 'Spanish', nativeName: 'Español'),
    WikipediaLanguage(code: 'fr', name: 'French', nativeName: 'Français'),
    WikipediaLanguage(code: 'de', name: 'German', nativeName: 'Deutsch'),
    WikipediaLanguage(code: 'it', name: 'Italian', nativeName: 'Italiano'),
    WikipediaLanguage(code: 'pt', name: 'Portuguese', nativeName: 'Português'),
    WikipediaLanguage(code: 'ru', name: 'Russian', nativeName: 'Русский'),
    WikipediaLanguage(code: 'ja', name: 'Japanese', nativeName: '日本語'),
    WikipediaLanguage(code: 'zh', name: 'Chinese', nativeName: '中文'),
    WikipediaLanguage(code: 'ar', name: 'Arabic', nativeName: 'العربية'),
    WikipediaLanguage(code: 'hi', name: 'Hindi', nativeName: 'हिन्दी'),
    WikipediaLanguage(code: 'ko', name: 'Korean', nativeName: '한국어'),
    WikipediaLanguage(code: 'nl', name: 'Dutch', nativeName: 'Nederlands'),
    WikipediaLanguage(code: 'pl', name: 'Polish', nativeName: 'Polski'),
    WikipediaLanguage(code: 'tr', name: 'Turkish', nativeName: 'Türkçe'),
    WikipediaLanguage(code: 'sv', name: 'Swedish', nativeName: 'Svenska'),
    WikipediaLanguage(code: 'no', name: 'Norwegian', nativeName: 'Norsk'),
    WikipediaLanguage(code: 'da', name: 'Danish', nativeName: 'Dansk'),
    WikipediaLanguage(code: 'fi', name: 'Finnish', nativeName: 'Suomi'),
    WikipediaLanguage(code: 'he', name: 'Hebrew', nativeName: 'עברית'),
  ];

  static WikipediaLanguage findByCode(String code) {
    return languages.firstWhere(
      (lang) => lang.code == code,
      orElse: () => languages[0], // Default to English
    );
  }
}

class WikipediaService {
  String _languageCode = 'en';

  void setLanguage(String languageCode) {
    _languageCode = languageCode;
  }

  String get currentLanguage => _languageCode;

  String get _baseUrl => 'https://$_languageCode.wikipedia.org/w/api.php';

  /// Search for Wikipedia articles near a geographic location
  Future<List<WikipediaArticle>> searchNearby({
    required double latitude,
    required double longitude,
    int radiusMeters = 1000,
    int limit = 10,
  }) async {
    print('\n=== Wikipedia Search ===');
    print('Language: $_languageCode');
    print('Center: $latitude, $longitude');
    print('Radius: ${radiusMeters}m');

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
    print('Request URL: $uri');

    try {
      final response = await http.get(uri);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final pages = data['query']?['pages'] as Map<String, dynamic>?;

        if (pages == null) {
          print('No pages found in response');
          return [];
        }

        print('Raw pages data: $pages');

        final articles = pages.values
            .map((page) => WikipediaArticle.fromJson(page as Map<String, dynamic>))
            .where((article) => article.hasValidCoordinates) // Filter out articles without valid coordinates
            .toList();

        print('✅ Found ${articles.length} articles with valid coordinates');

        // Log articles without coordinates
        final invalidCount = pages.length - articles.length;
        if (invalidCount > 0) {
          print('⚠️ Filtered out $invalidCount articles without valid coordinates');
        }

        return articles;
      } else {
        throw Exception('Failed to load Wikipedia articles: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Error fetching Wikipedia articles: $e');
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
