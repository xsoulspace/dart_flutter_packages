import 'package:flutter/foundation.dart';

import 'ordered_list.dart';

/// {@template ordered_list_notifier}
/// A reactive ordered list notifier that extends [ImmutableOrderedList] with change notification capabilities.
///
/// This class combines the immutability guarantees of [ImmutableOrderedList] with Flutter's
/// [ChangeNotifier] pattern, making it ideal for reactive UI programming. Any mutations
/// to the list automatically trigger [notifyListeners()], allowing widgets to rebuild
/// when the underlying data changes.
///
/// ```dart
/// class MyWidget extends StatefulWidget {
///   @override
///   State<MyWidget> createState() => _MyWidgetState();
/// }
///
/// class _MyWidgetState extends State<MyWidget> {
///   final listNotifier = OrderedListNotifier<String>();
///
///   @override
///   void initState() {
///     super.initState();
///     listNotifier.addListener(() => setState(() {}));
///   }
///
///   @override
///   Widget build(BuildContext context) {
///     return ListView.builder(
///       itemCount: listNotifier.length,
///       itemBuilder: (context, index) => Text(listNotifier.elementAt(index)),
///     );
///   }
///
///   @override
///   void dispose() {
///     listNotifier.dispose();
///     super.dispose();
///   }
/// }
/// ```
///
/// @ai Use this class in Flutter applications where you need reactive list updates.
/// Remember to call dispose() when the notifier is no longer needed to prevent memory leaks.
/// {@endtemplate}
class OrderedListNotifier<V> extends ImmutableOrderedList<V>
    with ChangeNotifier {
  /// {@template ordered_list_notifier_add}
  /// Adds the specified [value] to the end of this ordered list and notifies listeners.
  ///
  /// This method calls the superclass [add] method to perform the immutable update,
  /// then automatically calls [notifyListeners()] to trigger UI updates.
  ///
  /// @ai This method maintains immutability while providing reactive updates.
  /// {@endtemplate}
  @override
  @mustCallSuper
  void add(final V value) {
    super.add(value);
    notifyListeners();
  }

  /// {@template ordered_list_notifier_add_unique}
  /// Adds the specified [value] to the end of this ordered list if it doesn't already exist,
  /// and notifies listeners if the value was added.
  ///
  /// Returns `true` if the value was added, `false` if it already existed.
  /// Only calls [notifyListeners()] when a new item is actually added.
  ///
  /// @ai This method is efficient as it only triggers notifications when the list actually changes.
  /// {@endtemplate}
  @override
  @mustCallSuper
  bool addUnique(final V value) {
    final result = super.addUnique(value);
    if (result) notifyListeners();
    return result;
  }

  /// {@template ordered_list_notifier_remove}
  /// Removes the first occurrence of the specified [value] from this ordered list and notifies listeners.
  ///
  /// This method calls the superclass [remove] method to perform the immutable update,
  /// then automatically calls [notifyListeners()] to trigger UI updates.
  ///
  /// @ai This method maintains immutability while providing reactive updates for removals.
  /// {@endtemplate}
  @override
  @mustCallSuper
  void remove(final V value) {
    super.remove(value);
    notifyListeners();
  }

  /// {@template ordered_list_notifier_clear}
  /// Removes all items from this ordered list and notifies listeners.
  ///
  /// This method calls the superclass [clear] method to perform the immutable update,
  /// then automatically calls [notifyListeners()] to trigger UI updates.
  ///
  /// @ai Use this method to reset the list while ensuring all listeners are notified.
  /// {@endtemplate}
  @override
  @mustCallSuper
  void clear() {
    super.clear();
    notifyListeners();
  }
}
