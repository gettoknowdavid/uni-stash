import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:uni_stash_mobile/shared/widgets/spinner.dart';

/// Fullscreen, swipeable, pinch-to-zoom image gallery. Pushed as a
/// transparent dark route from the listing image carousel; swipe
/// horizontally to change image, double-tap to toggle zoom.
class FullscreenImageViewer extends StatefulWidget {
  const FullscreenImageViewer({
    required this.imageUrls,
    this.initialIndex = 0,
    super.key,
  });

  final List<String> imageUrls;
  final int initialIndex;

  /// Opens the viewer over the current navigator.
  static Future<void> show(
    BuildContext context, {
    required List<String> imageUrls,
    int initialIndex = 0,
  }) {
    return Navigator.of(context, rootNavigator: true).push(
      PageRouteBuilder<void>(
        opaque: false,
        transitionDuration: const Duration(milliseconds: 200),
        pageBuilder: (_, _, _) => FullscreenImageViewer(
          imageUrls: imageUrls,
          initialIndex: initialIndex,
        ),
        transitionsBuilder: (_, animation, _, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
  }

  @override
  State<FullscreenImageViewer> createState() => _FullscreenImageViewerState();
}

class _FullscreenImageViewerState extends State<FullscreenImageViewer> {
  late final PageController _pageController;
  late int _index;
  bool _zoomed = false;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _toggleZoom() => setState(() => _zoomed = !_zoomed);

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          PageView.builder(
            controller: _pageController,
            itemCount: widget.imageUrls.length,
            onPageChanged: (index) => setState(() {
              _index = index;
              _zoomed = false;
            }),
            itemBuilder: (context, _) => GestureDetector(
              onTap: _toggleZoom,
              onDoubleTap: _toggleZoom,
              child: Center(                  child: AnimatedScale(
                  scale: _zoomed ? 2.5 : 1.0,
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeInOut,
                  child: InteractiveViewer(
                    maxScale: 5.0,
                    panEnabled: _zoomed,
                    child: Image.network(
                      widget.imageUrls[_index],
                      fit: .contain,
                      loadingBuilder: (context, child, progress) =>
                          progress == null
                              ? child
                              : const Center(child: Spinner()),
                      errorBuilder: (_, _, _) => Icon(
                        LucideIcons.imageOff,
                        size: 48,
                        color: theme.colorScheme.mutedForeground,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Row(
              mainAxisAlignment: .spaceBetween,
              children: [
                Padding(
                  padding: const .all(16),
                  child: Text(
                    '${_index + 1} / ${widget.imageUrls.length}',
                    style: theme.textTheme.p.copyWith(color: Colors.white),
                  ),
                ),
                Padding(
                  padding: const .all(8),
                  child: ShadIconButton.ghost(
                    icon: const Icon(LucideIcons.x, color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
