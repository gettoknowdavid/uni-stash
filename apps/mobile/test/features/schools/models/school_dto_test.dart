import 'package:flutter_test/flutter_test.dart';
import 'package:uni_stash_mobile/features/schools/models/models.dart';
import 'package:uni_stash_mobile/features/schools/models/school_dto.dart';

void main() {
  group('School', () {
    test('serializes to JSON with correct keys', () {
      final school = School(
        id: 'school-1',
        name: 'MIT',
        slug: 'mit',
        domain: 'mit.edu',
        logoUrl: 'https://mit.edu/logo.png',
        createdAt: DateTime(2025),
      );
      final json = school.toJson();
      expect(json['id'], 'school-1');
      expect(json['name'], 'MIT');
      expect(json['slug'], 'mit');
      expect(json['domain'], 'mit.edu');
      expect(json['logo_url'], 'https://mit.edu/logo.png');
      expect(json['created_at'], '2025-01-01T00:00:00.000');
    });

    test('deserializes from JSON', () {
      final json = {
        'id': 'school-1',
        'name': 'MIT',
        'slug': 'mit',
        'domain': 'mit.edu',
        'logo_url': 'https://mit.edu/logo.png',
        'created_at': '2025-01-01T00:00:00.000',
      };
      final school = School.fromJson(json);
      expect(school.id, 'school-1');
      expect(school.name, 'MIT');
      expect(school.slug, 'mit');
      expect(school.domain, 'mit.edu');
      expect(school.logoUrl, 'https://mit.edu/logo.png');
    });

    test('handles null logoUrl', () {
      final json = {
        'id': 'school-1',
        'name': 'MIT',
        'slug': 'mit',
        'domain': 'mit.edu',
        'created_at': '2025-01-01T00:00:00.000',
      };
      final school = School.fromJson(json);
      expect(school.logoUrl, isNull);
    });

    test('roundtrip serialization preserves data', () {
      final original = School(
        id: 'school-1',
        name: 'MIT',
        slug: 'mit',
        domain: 'mit.edu',
        createdAt: DateTime(2025),
      );
      final restored = School.fromJson(original.toJson());
      expect(restored, original);
    });
  });

  group('ListSchoolsResponse', () {
    test('deserializes from JSON', () {
      final json = {
        'schools': [
          {
            'id': 's1',
            'name': 'MIT',
            'slug': 'mit',
            'domain': 'mit.edu',
            'created_at': '2025-01-01T00:00:00.000',
          },
        ],
        'next_cursor': 'cursor-abc',
      };
      final response = ListSchoolsResponse.fromJson(json);
      expect(response.schools.length, 1);
      expect(response.schools.first.name, 'MIT');
      expect(response.nextCursor, 'cursor-abc');
    });

    test('deserializes with null nextCursor', () {
      final json = {
        'schools': <dynamic>[],
      };
      final response = ListSchoolsResponse.fromJson(json);
      expect(response.schools, isEmpty);
      expect(response.nextCursor, isNull);
    });
  });

  group('ListSchoolsQuery', () {
    test('serializes to JSON with correct keys', () {
      const query = ListSchoolsQuery(q: 'test', limit: 10);
      final json = query.toJson();
      expect(json['q'], 'test');
      expect(json['limit'], 10);
    });

    test('defaults limit to 50', () {
      const query = ListSchoolsQuery();
      expect(query.limit, 50);
    });
  });
}
