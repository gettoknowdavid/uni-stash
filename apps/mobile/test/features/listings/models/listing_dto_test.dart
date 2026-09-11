import 'package:flutter_test/flutter_test.dart';
import 'package:uni_stash_mobile/features/listings/models/listing_dto.dart';
import 'package:uni_stash_mobile/features/listings/models/models.dart';

void main() {
  group('CreateListingRequest', () {
    test('serializes to JSON with correct keys', () {
      const request = CreateListingRequest(
        title: 'Test Title',
        condition: Condition.isNew,
        categoryId: 1,
        price: 100,
        description: 'Test Description',
      );
      final json = request.toJson();
      expect(json['title'], 'Test Title');
      expect(json['condition'], 'new');
      expect(json['category_id'], 1);
      expect(json['price'], 100);
      expect(json['description'], 'Test Description');
    });
    test('deserializes from JSON with snake_case keys', () {
      final json = {
        'title': 'Test Title',
        'condition': 'new',
        'category_id': 1,
        'price': 100,
        'description': 'Test Description',
      };
      final request = CreateListingRequest.fromJson(json);
      expect(request.title, 'Test Title');
      expect(request.condition, Condition.isNew);
      expect(request.categoryId, 1);
      expect(request.price, 100);
      expect(request.description, 'Test Description');
    });
    test('roundtrip serialization preserves data', () {
      const original = CreateListingRequest(
        title: 'Test Title',
        condition: Condition.isNew,
        categoryId: 1,
        price: 100,
        description: 'Test Description',
      );
      final restored = CreateListingRequest.fromJson(original.toJson());
      expect(restored, original);
    });
  });

  group('UpdateListingRequest', () {
    test('serializes to JSON with correct keys', () {
      const request = UpdateListingRequest(
        title: 'Test Title',
        condition: Condition.isNew,
        categoryId: 1,
        price: 100,
        description: 'Test Description',
      );
      final json = request.toJson();
      expect(json['title'], 'Test Title');
      expect(json['condition'], 'new');
      expect(json['category_id'], 1);
      expect(json['price'], 100);
      expect(json['description'], 'Test Description');
    });
    test('deserializes from JSON with snake_case keys', () {
      final json = {
        'title': 'Test Title',
        'condition': 'new',
        'category_id': 1,
        'price': 100,
        'description': 'Test Description',
      };
      final request = UpdateListingRequest.fromJson(json);
      expect(request.title, 'Test Title');
      expect(request.condition, Condition.isNew);
      expect(request.categoryId, 1);
      expect(request.price, 100);
      expect(request.description, 'Test Description');
    });
    test('roundtrip serialization preserves data', () {
      const original = UpdateListingRequest(
        title: 'Test Title',
        condition: Condition.isNew,
        categoryId: 1,
        price: 100,
        description: 'Test Description',
      );
      final restored = UpdateListingRequest.fromJson(original.toJson());
      expect(restored, original);
    });
  });

  group('ListListingsResponse', () {
    test('deserializes from JSON', () {});
  });

  group('ListingDetailResponse', () {
    test('deserializes from JSON', () {
      final json = {
        'id': 'uuid-0001',
        'title': 'Test Title',
        'description': 'Test Description',
        'condition': 'new',
        'status': 'active',
        'created_at': '2023-01-01T00:00:00Z',
        'price': 100,
        'seller': {
          'id': 'uuid-1234',
          'display_name': 'Test Seller',
        },
        'category': {
          'id': 1,
          'slug': 'test-category',
          'label': 'Test Category',
        },
        'images': [
          {
            'id': 'uuid-1234',
            'object_key': 'test.jpg',
            'position': 0,
          },
          {
            'id': 'uuid-5678',
            'object_key': 'test2.jpg',
            'position': 1,
          },
        ],
      };
      final response = ListingDetailResponse.fromJson(json);
      expect(response.id, 'uuid-0001');
      expect(response.title, 'Test Title');
      expect(response.description, 'Test Description');
      expect(response.condition, Condition.isNew);
      expect(response.status, ListingStatus.active);
      expect(response.createdAt, DateTime.parse('2023-01-01T00:00:00Z'));
      expect(response.price, 100);
      expect(response.seller.id, 'uuid-1234');
      expect(response.seller.displayName, 'Test Seller');
      expect(response.category.id, 1);
      expect(response.category.slug, 'test-category');
      expect(response.category.label, 'Test Category');
      expect(response.images.length, 2);
      expect(response.images[0].id, 'uuid-1234');
      expect(response.images[0].objectKey, 'test.jpg');
      expect(response.images[0].position, 0);
      expect(response.images[1].id, 'uuid-5678');
      expect(response.images[1].objectKey, 'test2.jpg');
      expect(response.images[1].position, 1);
    });
  });
}
