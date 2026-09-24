/// The chat whose detail page is currently on screen, if any.
///
/// Read by the realtime coordinator and the push handler to decide whether
/// an incoming message needs an in-app notification: messages for the chat
/// the user is already viewing update the list in place (guide 7.8), every
/// other chat raises a tappable notification instead.
abstract final class OpenChat {
  /// Set by `ChatDetailPage.initState`, cleared by its `dispose` (only when
  /// it still matches — a newer page may have opened in between).
  static String? id;

  static bool isOpen(String chatId) => id == chatId;

  static void open(String chatId) => id = chatId;

  static void close(String chatId) {
    if (id == chatId) id = null;
  }
}
