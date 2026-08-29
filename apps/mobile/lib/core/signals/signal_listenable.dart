import 'package:flutter/foundation.dart';
import 'package:signals_flutter/signals_flutter.dart';

/// Bridges a Signals [ReadonlySignal] to a Flutter [Listenable] for APIs
/// that expect one (e.g. `GoRouter.refreshListenable`). Never cast a
/// Signal directly to `ValueListenable` — it doesn't implement that
/// contract; use this instead.
class SignalListenable extends ChangeNotifier {
  SignalListenable(ReadonlySignal<Object?> source) {
    _dispose = effect(() {
      source.value;
      notifyListeners();
    });
  }

  late final void Function() _dispose;

  @override
  void dispose() {
    _dispose();
    super.dispose();
  }
}
