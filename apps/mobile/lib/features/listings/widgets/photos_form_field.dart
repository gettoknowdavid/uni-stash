import 'dart:async';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/widgets.dart' as flutter;
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:uni_stash_mobile/features/listings/models/models.dart';

/// A [ShadForm] form field managing the list of photos of a listing.
///
/// Renders one tile per [ListingImage] plus an "add" tile. Photo tiles show
/// a small remove button; the add tile invokes [onAddPhotos] (e.g. an
/// image_picker flow) with the number of free slots left and appends the
/// returned photos, never exceeding [maxPhotos].
///
/// The form value is the current `List<ListingImage>`; the built-in validator
/// requires at least one photo and at most [maxPhotos].
///
/// Previews: freshly picked photos carry a [LocalImage.localPath] and render
/// from the local file; server photos (edit flow) render from the
/// [ServerImage.url] with `cached_network_image`, so reopening the editor
/// does not re-download already-seen photos.
class ShadPhotosFormField extends ShadFormBuilderField<List<ListingImage>> {
  ShadPhotosFormField({
    required Future<List<ListingImage>> Function(int remainingSlots)?
    onAddPhotos,
    super.key,
    super.id,
    super.label,
    super.description,
    FormFieldValidator<List<ListingImage>>? validator,
    super.autovalidateMode,
    super.onSaved,
    super.enabled = true,
    int maxPhotos = 3,
    ValueChanged<List<ListingImage>>? onPhotosChanged,
    this.tileSize = 80,
  }) : _maxPhotos = maxPhotos,
       _onAddPhotos = onAddPhotos,
       _onPhotosChanged = onPhotosChanged,
       super(
         initialValue: const <ListingImage>[],
         validator: validator ?? _defaultValidator(maxPhotos),
         builder: (state) {
           final fieldState =
               state
                   as ShadFormBuilderFieldState<
                     ShadFormBuilderField<List<ListingImage>>,
                     List<ListingImage>
                   >;
           final photos = fieldState.value ?? const <ListingImage>[];
           final canAdd = fieldState.enabled && photos.length < maxPhotos;

           void update(List<ListingImage> next) {
             final reindexed = _reindexed(next);
             fieldState.didChange(reindexed);
             onPhotosChanged?.call(reindexed);
           }

           return Row(
             spacing: 8,
             children: [
               for (var i = 0; i < photos.length; i++)
                 _PhotoTile(
                   key: ValueKey(photos[i].id),
                   photo: photos[i],
                   tileSize: tileSize,
                   enabled: fieldState.enabled,
                   onRemove: () => update([...photos]..removeAt(i)),
                 ),
               if (canAdd)
                 ShadButton.outline(
                   height: tileSize,
                   width: tileSize,
                   onPressed: onAddPhotos == null
                       ? null
                       : () async {
                           final added = await onAddPhotos(
                             maxPhotos - photos.length,
                           );
                           if (!fieldState.mounted) return;
                           if (added.isEmpty) return;
                           update(
                             [...photos, ...added].take(maxPhotos).toList(),
                           );
                         },
                   child: const Icon(LucideIcons.plus),
                 ),
             ],
           );
         },
       );

  final int _maxPhotos;
  final Future<List<ListingImage>> Function(int remainingSlots)? _onAddPhotos;
  final ValueChanged<List<ListingImage>>? _onPhotosChanged;

  /// Maximum number of photos the field accepts.
  int get maxPhotos => _maxPhotos;

  /// Called when the add tile is tapped with the number of free slots left;
  /// return the newly picked photos.
  Future<List<ListingImage>> Function(int remainingSlots)? get onAddPhotos =>
      _onAddPhotos;

  /// Notified with the new list every time photos change.
  ValueChanged<List<ListingImage>>? get onPhotosChanged => _onPhotosChanged;

  /// Edge size of each photo / add tile.
  final double tileSize;

  static String? Function(List<ListingImage>?) _defaultValidator(
    int maxPhotos,
  ) {
    return (photos) {
      if (photos == null || photos.isEmpty) {
        return 'Please add at least one photo.';
      }
      if (photos.length > maxPhotos) {
        return 'You can add up to $maxPhotos photos.';
      }
      return null;
    };
  }

  static List<ListingImage> _reindexed(List<ListingImage> photos) {
    return [
      for (var i = 0; i < photos.length; i++)
        photos[i].when(
          server: (id, url, _) =>
              ListingImage.server(id: id, url: url, position: i),
          local: (id, _, localPath) =>
              ListingImage.local(id: id, position: i, localPath: localPath),
        ),
    ];
  }
}

class _PhotoTile extends StatelessWidget {
  const _PhotoTile({
    required this.photo,
    required this.tileSize,
    required this.enabled,
    required this.onRemove,
    super.key,
  });

  final ListingImage photo;
  final double tileSize;
  final bool enabled;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final placeholder = Icon(
      LucideIcons.image,
      size: 24,
      color: theme.colorScheme.mutedForeground,
    );

    final preview = photo.when(
      local: (id, position, localPath) {
        return flutter.Image.file(
          File(localPath),
          width: tileSize,
          height: tileSize,
          fit: BoxFit.cover,
        );
      },
      server: (id, url, position) {
        return CachedNetworkImage(
          imageUrl: url,
          width: tileSize,
          height: tileSize,
          fit: BoxFit.cover,
          placeholder: (_, _) => Center(child: placeholder),
          errorWidget: (_, _, _) => Center(child: placeholder),
        );
      },
    );

    return SizedBox(
      width: tileSize,
      height: tileSize,
      child: Stack(
        children: [
          Container(
            width: tileSize,
            height: tileSize,
            decoration: BoxDecoration(
              color: theme.colorScheme.muted,
              border: Border.all(color: theme.colorScheme.border),
            ),
            clipBehavior: Clip.antiAlias,
            child: preview,
          ),
          if (enabled)
            Positioned(
              top: 2,
              right: 2,
              child: ShadIconButton.outline(
                width: 22,
                height: 22,
                iconSize: 14,
                padding: .zero,
                icon: const Icon(LucideIcons.x),
                onPressed: onRemove,
              ),
            ),
        ],
      ),
    );
  }
}
