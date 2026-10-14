// ignore_for_file: unsafe_variance

import 'dart:collection';

import 'package:infinite_scroll_pagination/infinite_scroll_pagination.dart';

typedef PagingControllerHashFunction<TItem> = int Function(TItem);
typedef PagingControllerEqualityFunction<TItem> = bool Function(TItem, TItem);

extension _ListX<T> on List<T> {
  /// Splits [items] into [sublistCount] sublists, distributing items as evenly as possible.
  ///
  /// Always returns exactly [sublistCount] sublists, even if some are empty.
  /// If items cannot be divided evenly, the first pages will have one extra item.
  Iterable<List<T>> splitIntoSublists(int sublistCount) sync* {
    if (sublistCount <= 0) return;

    final int totalItems = length;
    final int baseSize = totalItems ~/ sublistCount;
    final int remainder = totalItems % sublistCount;
    int start = 0;

    for (int i = 0; i < sublistCount; i++) {
      final extra = i < remainder ? 1 : 0;
      final end = start + baseSize + extra;
      if (start < totalItems) {
        yield sublist(start, end.clamp(start, totalItems));
      } else {
        yield <T>[]; // Always yield an empty list if no items left
      }
      start = end;
    }
  }
}

/// {@template hash_paging_controller}
/// A [PagingController] extension that uses hash-based deduplication
/// to prevent duplicate items in the paginated list.
/// {@endtemplate}
class HashPagingController<TKey, TItem> extends PagingController<TKey, TItem> {
  /// {@macro hash_paging_controller}
  HashPagingController({
    required super.getNextPageKey,
    required FetchPageCallback<TKey, TItem> fetchPage,
    super.value,
    this.hashFunction,
    this.equalityFunction,
  }) : _userFetchPage = fetchPage,
       _getNextPageKey = getNextPageKey,
       super(fetchPage: (pageKey) => []);

  final PagingControllerHashFunction<TItem>? hashFunction;
  final PagingControllerEqualityFunction<TItem>? equalityFunction;
  final FetchPageCallback<TKey, TItem> _userFetchPage;
  final NextPageKeyCallback<TKey, TItem> _getNextPageKey;

  @override
  Future<void> fetchNextPage() async {
    // We override fetchNextPage to apply deduplication
    if (operation != null) return;

    final op = operation = Object();

    value = value.copyWith(isLoading: true, error: null);

    PagingState<TKey, TItem> state = value;

    try {
      if (!state.hasNextPage) return;

      final nextPageKey = _getNextPageKey(state);
      if (nextPageKey == null) {
        state = state.copyWith(hasNextPage: false);
        return;
      }

      final fetchResult = _userFetchPage(nextPageKey);
      List<TItem> newItems;

      if (fetchResult is Future) {
        newItems = await fetchResult;
      } else {
        newItems = fetchResult;
      }

      // Apply deduplication before adding to state
      final existingItems =
          state.pages?.expand((page) => page).toList() ?? [];
      final deduplicatedItems = _deduplicateItems(existingItems, newItems);
      final keys = [...?state.keys, nextPageKey];
      final pages = deduplicatedItems.splitIntoSublists(keys.length).toList();
      state = state.copyWith(pages: pages, keys: keys);
    } catch (error) {
      state = state.copyWith(error: error);

      if (error is! Exception) {
        rethrow;
      }
    } finally {
      if (op == operation) {
        value = state.copyWith(isLoading: false);
        operation = null;
      }
    }
  }

  /// Appends [newItems] to the previously loaded ones and sets hasNextPage
  /// to false.
  void appendLastPage(List<TItem> newItems) =>
      appendPageWithDeduplication(newItems, hasNextPage: false);

  /// Appends [newItems] to the previously loaded ones.
  void appendPageWithDeduplication(
    List<TItem> newItems, {
    required bool hasNextPage,
  }) {
    if (!_mounted) return;
    final deduplicatedItems = _deduplicateItems(items ?? [], newItems);
    value = value.copyWith(
      pages: [...?value.pages, deduplicatedItems],
      hasNextPage: hasNextPage,
    );
  }

  /// Prepends [newItems] to the previously loaded ones and sets hasNextPage
  /// to the provided value.
  void prependLastPage(List<TItem> newItems) =>
      prependPage(newItems, hasNextPage: false);

  void prependPage(
    List<TItem> newItems, {
    required bool hasNextPage,
  }) {
    if (!_mounted) return;
    final deduplicatedItems = _deduplicateItems(newItems, items ?? []);
    value = value.copyWith(
      pages: [deduplicatedItems],
      hasNextPage: hasNextPage,
    );
  }

  List<TItem> _deduplicateItems(
    List<TItem> existingItems,
    List<TItem> newItems,
  ) {
    final allItems =
        LinkedHashSet<TItem>(
            hashCode: hashFunction ?? (e) => e.hashCode,
            equals:
                equalityFunction ??
                (a, b) => a.hashCode == b.hashCode,
          )
          ..addAll(existingItems)
          ..addAll(newItems);
    return allItems.toList();
  }

  void refreshWithoutNotify() {
    value = value.reset();
  }

  void insertElement(TItem element, {int at = 0}) {
    final newItems = [...?items]..insert(at, element);
    _updateItemList(newItems);
  }

  void insertElements(Iterable<TItem> elements, {int at = 0}) {
    final newItems = [...?items]..insertAll(at, elements);
    _updateItemList(newItems);
  }

  /// removes element from listing at given [oldIndex], then reinserts it
  /// at [newIndex]
  void moveElementByIndex({
    required int oldIndex,
    required TItem element,

    /// target index after element removal
    int newIndex = 0,
  }) {
    if (oldIndex < 0) return;
    final newItems = [...?items]
      ..removeAt(oldIndex)
      ..insert(newIndex, element);
    _updateItemList(newItems);
  }

  /// removes element from listing at given [index]
  TItem? removeElementByIndex({required int index}) {
    if (index < 0) return null;
    final currentItems = items ?? [];
    if (currentItems.isEmpty) return null;
    final item = currentItems[index];
    final newItems = [...currentItems]..removeAt(index);
    _updateItemList(newItems);
    return item;
  }

  TItem? removeElementWhere({
    required bool Function(TItem element) test,
  }) {
    final int index = items?.indexWhere(test) ?? -1;
    return removeElementByIndex(index: index);
  }

  List<TItem> removeElementsWhere({
    required bool Function(TItem element) test,
  }) {
    final list = [...?items];
    if (list.isEmpty) return [];
    final itemsToDelete = list.indexed.where((e) => test(e.$2)).toList()
      ..sort(
        /// sort from max index to short index to
        /// make items removal easier
        (indexEl1, indexEl2) => indexEl2.$1.compareTo(indexEl1.$1),
      );
    final deletedItems = itemsToDelete
        .map((e) => removeElementByIndex(index: e.$1))
        .whereType<TItem>()
        .toList();
    return deletedItems;
  }

  void removeElement({
    required TItem element,
    bool Function(TItem element)? test,
  }) {
    final testCallback = test ?? (a) => a == element;
    final int index = items?.indexWhere(testCallback) ?? -1;

    removeElementByIndex(index: index);
  }

  void replaceElementByIndex({
    required int index,
    required TItem element,
    bool shouldAddOnNotFound = false,
  }) {
    if (index < 0) {
      if (shouldAddOnNotFound) {
        insertElement(element);
      } else {
        return;
      }
    } else {
      final newItems = [...?items]
        ..removeAt(index)
        ..insert(index, element);
      _updateItemList(newItems);
    }
  }

  void replaceElement({
    required TItem element,
    bool shouldAddOnNotFound = false,
    bool shouldMoveToFirst = false,
    bool Function(TItem a, TItem b)? equals,
    int? index,
  }) {
    final bool Function(TItem) comparator = equals == null
        ? ((a) => a == element)
        : (a) => equals(a, element);
    final int eIndex = index ?? (items?.indexWhere(comparator) ?? -1);

    replaceElementByIndex(
      index: eIndex,
      element: element,
      shouldAddOnNotFound: shouldAddOnNotFound,
    );
    if (shouldMoveToFirst) {
      moveElementByIndex(oldIndex: eIndex, element: element);
    }
  }

  void _updateItemList(List<TItem> newItems) {
    final resettedState = value.reset();
    final key = value.keys?.firstOrNull;
    value = resettedState.copyWith(
      pages: [newItems],
      keys: key == null ? null : [key],
    );
  }

  bool _mounted = true;
  @override
  void dispose() {
    _mounted = false;
    super.dispose();
  }
}
