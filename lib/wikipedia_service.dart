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
