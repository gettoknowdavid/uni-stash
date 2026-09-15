import 'dart:convert';

/// Persisted state for an in-progress listing submission.
///
/// Saved to local storage on every submit attempt so that if the app crashes
/// or is killed, the user can resume from where they left off. The [listingId]
/// field is the key: when it's non-null the listing already exists server-side
/// and the next submit should PATCH instead of POST.
class ListingDraft {
  const ListingDraft({
    required this.title,
    required this.description,
    required this.categoryId,
    required this.condition,
    required this.barterOnly,
    required this.imagePaths,
    this.price,
    this.barterRequest,
    this.listingId,
  });

  factory ListingDraft.fromJson(Map<String, dynamic> json) {
    return ListingDraft(
      title: json['title'] as String? ?? '',
      description: json['description'] as String? ?? '',
      categoryId: json['category_id'] as int? ?? 0,
      condition: json['condition'] as String? ?? 'new',
      barterOnly: json['barter_only'] as bool? ?? false,
      imagePaths: (json['image_paths'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
      price: json['price'] as int?,
      barterRequest: json['barter_request'] as String?,
      listingId: json['listing_id'] as String?,
    );
  }

  final String title;
  final String description;
  final int categoryId;
  final String condition;
  final bool barterOnly;
  final List<String> imagePaths;
  final int? price;
  final String? barterRequest;
  final String? listingId;

  /// Whether this draft represents a listing that was already created
  /// server-side (i.e. a retry is needed instead of a fresh create).
  bool get hasListingId => listingId != null && listingId!.isNotEmpty;

  Map<String, dynamic> toJson() => {
        'title': title,
        'description': description,
        'category_id': categoryId,
        'condition': condition,
        'barter_only': barterOnly,
        'image_paths': imagePaths,
        'price': price,
        'barter_request': barterRequest,
        'listing_id': listingId,
      };

  String encode() => jsonEncode(toJson());

  static ListingDraft? decode(String raw) {
    try {
      return ListingDraft.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } on Object {
      return null;
    }
  }
}
