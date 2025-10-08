// ignore_for_file: unsafe_variance

import 'dart:collection';

import 'package:infinite_scroll_pagination/infinite_scroll_pagination.dart';

typedef PagingControllerHashFunction<TItem> = int Function(TItem);
typedef PagingControllerEqualityFunction<TItem> = bool Function(TItem, TItem);

/// {@template hash_paging_controller}
/// A [PagingController] extension that uses hash-based deduplication
/// to prevent duplicate items in the paginated list.
/// {@endtemplate}
class HashPagingController<TKey, TItem> extends PagingController<TKey, TItem> {
  /// {@macro hash_paging_controller}
  HashPagingController({
    required super.getNextPageKey,
    required final FetchPageCallback<TKey, TItem> fetchPage,
    super.value,
    this.hashFunction,
    this.equalityFunction,
  }) : _userFetchPage = fetchPage,
       _getNextPageKey = getNextPageKey,
       super(fetchPage: (final pageKey) => []);

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

      state = value;

      // Apply deduplication before adding to state
      final existingItems =
          state.pages?.expand((final page) => page).toList() ?? [];
      final deduplicatedItems = _deduplicateItems(existingItems, newItems);

      state = state.copyWith(
        pages: [...?state.pages, deduplicatedItems],
        keys: [...?state.keys, nextPageKey],
      );
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
  void appendLastPage(final List<TItem> newItems) =>
      appendPageWithDeduplication(newItems, hasNextPage: false);

  /// Appends [newItems] to the previously loaded ones.
  void appendPageWithDeduplication(
    final List<TItem> newItems, {
    required final bool hasNextPage,
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
  void prependLastPage(final List<TItem> newItems) =>
      prependPage(newItems, hasNextPage: false);

  void prependPage(
    final List<TItem> newItems, {
    required final bool hasNextPage,
  }) {
    if (!_mounted) return;
    final deduplicatedItems = _deduplicateItems(newItems, items ?? []);
    value = value.copyWith(
      pages: [deduplicatedItems],
      hasNextPage: hasNextPage,
    );
  }

  List<TItem> _deduplicateItems(
    final List<TItem> existingItems,
    final List<TItem> newItems,
  ) {
    final allItems =
        LinkedHashSet<TItem>(
            hashCode: hashFunction ?? (final e) => e.hashCode,
            equals:
                equalityFunction ??
                (final a, final b) => a.hashCode == b.hashCode,
          )
          ..addAll(existingItems)
          ..addAll(newItems);
    return allItems.toList();
  }

  void refreshWithoutNotify() {
    value = value.reset();
  }

  void insertElement(final TItem element, {final int at = 0}) {
    final newItems = [...?items]..insert(at, element);
    _updateItemList(newItems);
  }

  void insertElements(final Iterable<TItem> elements, {final int at = 0}) {
    final newItems = [...?items]..insertAll(at, elements);
    _updateItemList(newItems);
  }

  /// removes element from listing at given [oldIndex], then reinserts it
  /// at [newIndex]
  void moveElementByIndex({
    required final int oldIndex,
    required final TItem element,

    /// target index after element removal
    final int newIndex = 0,
  }) {
    if (oldIndex < 0) return;
    final newItems = [...?items]
      ..removeAt(oldIndex)
      ..insert(newIndex, element);
    _updateItemList(newItems);
  }

  /// removes element from listing at given [index]
  TItem? removeElementByIndex({required final int index}) {
    if (index < 0) return null;
    final currentItems = items ?? [];
    if (currentItems.isEmpty) return null;
    final item = currentItems[index];
    final newItems = [...currentItems]..removeAt(index);
    _updateItemList(newItems);
    return item;
  }

  TItem? removeElementWhere({
    required final bool Function(TItem element) test,
  }) {
    final int index = items?.indexWhere(test) ?? -1;
    return removeElementByIndex(index: index);
  }

  List<TItem> removeElementsWhere({
    required final bool Function(TItem element) test,
  }) {
    final list = [...?items];
    if (list.isEmpty) return [];
    final itemsToDelete = list.indexed.where((final e) => test(e.$2)).toList()
      ..sort(
        /// sort from max index to short index to
        /// make items removal easier
        (final indexEl1, final indexEl2) => indexEl2.$1.compareTo(indexEl1.$1),
      );
    final deletedItems = itemsToDelete
        .map((final e) => removeElementByIndex(index: e.$1))
        .whereType<TItem>()
        .toList();
    return deletedItems;
  }

  void removeElement({required final TItem element}) {
    final int index = items?.indexWhere((final a) => a == element) ?? -1;
    removeElementByIndex(index: index);
  }

  void replaceElementByIndex({
    required final int index,
    required final TItem element,
    final bool shouldAddOnNotFound = false,
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
    required final TItem element,
    final bool shouldAddOnNotFound = false,
    final bool Function(TItem a, TItem b)? equals,
    final int? index,
  }) {
    final bool Function(TItem) comparator = equals == null
        ? ((final a) => a == element)
        : (final a) => equals(a, element);
    final int eIndex = index ?? (items?.indexWhere(comparator) ?? -1);

    replaceElementByIndex(
      index: eIndex,
      element: element,
      shouldAddOnNotFound: shouldAddOnNotFound,
    );
  }

  void _updateItemList(final List<TItem> newItems) {
    value = value.copyWith(pages: [newItems]);
  }

  bool _mounted = true;
  @override
  void dispose() {
    _mounted = false;
    super.dispose();
  }
}
