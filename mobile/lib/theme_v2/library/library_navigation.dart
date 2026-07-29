import 'package:flutter/foundation.dart';

enum LibrarySurface {
  hub,
  containerIndex,
  allContainers,
  pinnedConfiguration,
  assetContainer,
}

@immutable
class LibraryChromeSpec {
  const LibraryChromeSpec({required this.topNav, required this.dock});

  final bool topNav;
  final bool dock;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LibraryChromeSpec &&
          topNav == other.topNav &&
          dock == other.dock;

  @override
  int get hashCode => Object.hash(topNav, dock);
}

class LibraryNavigationController extends ChangeNotifier {
  final List<LibrarySurface> _stack = [LibrarySurface.hub];

  LibrarySurface get surface => _stack.last;
  bool get canPop => _stack.length > 1;

  LibraryChromeSpec get chrome => switch (surface) {
    LibrarySurface.hub ||
    LibrarySurface.containerIndex ||
    LibrarySurface.assetContainer => const LibraryChromeSpec(
      topNav: true,
      dock: true,
    ),
    LibrarySurface.allContainers => const LibraryChromeSpec(
      topNav: true,
      dock: false,
    ),
    LibrarySurface.pinnedConfiguration => const LibraryChromeSpec(
      topNav: false,
      dock: true,
    ),
  };

  void open(LibrarySurface next) {
    if (next == surface) return;
    _stack.add(next);
    notifyListeners();
  }

  bool back() {
    if (!canPop) return false;
    _stack.removeLast();
    notifyListeners();
    return true;
  }

  void home() {
    if (_stack.length == 1) return;
    _stack
      ..clear()
      ..add(LibrarySurface.hub);
    notifyListeners();
  }
}
