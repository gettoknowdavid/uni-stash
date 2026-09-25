/// Wire models for the ratings & reviews feature. Hand-written (not
/// freezed) — small, stable shapes mirroring the backend JSON.
class Review {
  const Review({
    required this.id,
    required this.saleId,
    required this.authorId,
    required this.revieweeId,
    required this.rating,
    required this.authorName,
    required this.revieweeName,
    required this.listingTitle,
    required this.createdAt,
    this.comment,
  });

  factory Review.fromJson(Map<String, dynamic> json) => Review(
        id: json['id'] as String,
        saleId: json['sale_id'] as String,
        authorId: json['author_id'] as String,
        revieweeId: json['reviewee_id'] as String,
        rating: json['rating'] as int,
        comment: json['comment'] as String?,
        authorName: json['author_name'] as String? ?? 'User',
        revieweeName: json['reviewee_name'] as String? ?? 'User',
        listingTitle: json['listing_title'] as String? ?? '',
        createdAt: DateTime.parse(json['created_at'] as String),
      );

  final String id;
  final String saleId;
  final String authorId;
  final String revieweeId;
  final int rating;
  final String? comment;
  final String authorName;
  final String revieweeName;
  final String listingTitle;
  final DateTime createdAt;
}

class UserReviewsResponse {
  const UserReviewsResponse({
    required this.reviews,
    required this.reviewCount,
    this.averageRating,
  });

  factory UserReviewsResponse.fromJson(Map<String, dynamic> json) =>
      UserReviewsResponse(
        reviews: (json['reviews'] as List<dynamic>)
            .map((raw) => Review.fromJson(raw as Map<String, dynamic>))
            .toList(),
        averageRating: (json['average_rating'] as num?)?.toDouble(),
        reviewCount: json['review_count'] as int? ?? 0,
      );

  final List<Review> reviews;
  final double? averageRating;
  final int reviewCount;
}

class CreateReviewRequest {
  const CreateReviewRequest({required this.rating, this.comment});

  Map<String, dynamic> toJson() => {'rating': rating, 'comment': comment};

  final int rating;
  final String? comment;
}
