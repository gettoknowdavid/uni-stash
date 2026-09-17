import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:uni_stash_mobile/theme/_theme.dart';

/// A square avatar that shows a network photo when [photoUrl] is provided,
/// falling back to initials derived from [name].
///
/// When [verified] is true a tilted "VERIFIED" badge is drawn in the top-left
/// corner — the same visual used on the profile page.
///
/// ```dart
/// UsAvatar(name: 'Adaeze B.', size: 40)
/// UsAvatar(name: 'Ada L.', photoUrl: url, verified: true, size: 112)
/// ```
class UsAvatar extends StatelessWidget {
  const UsAvatar({
    required this.name,
    this.photoUrl,
    this.size = 112,
    this.verified = false,
    this.verifiedLabel = 'VERIFIED',
    super.key,
  });

  /// User's display name — used to derive initials when no [photoUrl] is set.
  final String name;

  /// Optional network image URL. When `null` the avatar renders initials.
  final String? photoUrl;

  /// Width and height of the avatar square.
  final double size;

  /// Whether to show the tilted "VERIFIED" badge.
  final bool verified;

  /// Label text on the verified badge.
  final String verifiedLabel;

  // ------------------------------------------------------------------
  // Helpers
  // ------------------------------------------------------------------

  String get _initials {
    final parts = name.trim().split(RegExp(r'\s+'))
      ..removeWhere((part) => part.isEmpty);
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  // ------------------------------------------------------------------
  // Build
  // ------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final borderWidth = size > 60 ? 2.0 : 1.0;

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: .none,
        children: [
          // ----- Image or initials fallback -----
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: theme.colorScheme.muted,
              border: Border.all(
                color: theme.colorScheme.border,
                width: borderWidth,
              ),
            ),
            clipBehavior: .hardEdge,
            child: photoUrl != null && photoUrl!.isNotEmpty
                ? CachedNetworkImage(
                    imageUrl: photoUrl!,
                    fit: BoxFit.cover,
                    placeholder: (_, _) => Center(
                      child: Text(
                        _initials,
                        style: _initialsStyle(theme),
                      ),
                    ),
                    errorWidget: (_, _, _) => Center(
                      child: Text(
                        _initials,
                        style: _initialsStyle(theme),
                      ),
                    ),
                  )
                : Center(
                    child: Text(
                      _initials,
                      style: _initialsStyle(theme),
                    ),
                  ),
          ),

          // ----- Verified badge -----
          if (verified)
            Positioned(
              top: size * 0.054, // ~6 px on 112, scales proportionally
              left: -(size * 0.107), // ~-12 px on 112
              child: Transform.rotate(
                angle: -0.06,
                child: Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: size * 0.071, // ~8 px on 112
                    vertical: size * 0.036, // ~4 px on 112
                  ),
                  color: UsPrimitives.sage300,
                  child: Text(
                    verifiedLabel,
                    style: theme.textTheme.labelMd.copyWith(
                      fontWeight: FontWeight.w700,
                      color: UsPrimitives.neutral900,
                      fontSize: size > 60 ? null : size * 0.107,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  TextStyle _initialsStyle(ShadThemeData theme) {
    final fontSize = size > 60 ? theme.textTheme.h1.fontSize : size * 0.357;
    return theme.textTheme.h1.copyWith(
      fontSize: fontSize,
      color: theme.colorScheme.textSecondary,
    );
  }
}
