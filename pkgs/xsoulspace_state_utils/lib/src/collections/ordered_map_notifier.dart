import 'package:flutter/foundation.dart';

import 'ordered_map.dart';

class OrderedMapNotifier<K, V> extends ImmutableOrderedMap<K, V>
    with ChangeNotifier {
  OrderedMapNotifier({required super.toKey});
  @override
  @mustCallSuper
  void upsert(final K key, final V value, {final bool putFirst = true}) {
    super.upsert(key, value, putFirst: putFirst);
    notifyListeners();
  }

  @override
  @mustCallSuper
  void remove(final K key) {
    super.remove(key);
    notifyListeners();
  }

  @override
  @mustCallSuper
  void clear() {
    super.clear();
    notifyListeners();
  }
}
