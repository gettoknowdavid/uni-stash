/// Application-wide constants.
final class UsConstants {
  const UsConstants._();

  /// Maximum number of images allowed per listing.
  static const int maxImagesPerListing = 3;

  /// Default page size for paginated API requests.
  static const int defaultPageSize = 20;

  /// Seconds before an access token expires to trigger a refresh.
  static const Duration tokenRefreshBuffer = Duration(seconds: 60);

  /// Client-side rate-limit safety threshold (requests per minute).
  /// Server-side limits from `Retry-After` headers take precedence.
  static const int rateLimitThreshold = 500;
}
