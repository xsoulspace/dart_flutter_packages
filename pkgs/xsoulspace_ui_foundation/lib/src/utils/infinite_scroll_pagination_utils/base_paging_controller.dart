import 'package:flutter/foundation.dart';
import 'package:xsoulspace_foundation/xsoulspace_foundation.dart';

import 'infinite_scroll_pagination_utils.dart';

extension type UnifiedPagingControllerId(String value) {}

typedef PagingControllerLoadFunction<TModel> =
    Future<PagingControllerPageModel<TModel>> Function(int page);

abstract class PagingControllerRequestsBuilder<TModel> {
  PagingControllerRequestsBuilder({required this.onLoadData});
  final PagingControllerLoadFunction<TModel> onLoadData;
}

/// {@template base_paging_controller}
/// Base paging controller for paginated data loading with built-in support
/// for empty items and request building.
///
/// Usage:
/// ```dart
/// class MyPagingController extends BasePagingController<MyItem> {
///   @override
///   PagingControllerRequestsBuilder<MyItem> get requestBuilder =>
///     PagingControllerRequestsBuilder(onLoadData: _loadData);
///
///   Future<PagingControllerPageModel<MyItem>> _loadData(int page) async {
///     // Load and return page data
///   }
/// }
/// ```
/// {@endtemplate}
abstract base class BasePagingController<TItem> implements Disposable {
  /// {@macro base_paging_controller}
  BasePagingController({
    this.addEmptyFirstItem = false,
    this.emptyItemBuilder,
    final int firstPageKey = 1,
  }) : _firstPageKey = firstPageKey,
       assert(
         // ignore: avoid_bool_literals_in_conditional_expressions
         addEmptyFirstItem ? emptyItemBuilder != null : true,
         'emptyItemBuilder must not be null',
       ) {
    pager.addListener(_onPagerChanged);
  }
  late final int _firstPageKey;
  final bool addEmptyFirstItem;
  final ValueGetter<TItem>? emptyItemBuilder;
  late final pager = HashPagingController<int, TItem>(
    getNextPageKey: (final state) {
      if (_isLastPage) return null;
      final lastKey = state.keys?.lastOrNull ?? 0;
      return lastKey + 1;
    },
    fetchPage: _fetchPage,
  );
  final id = UnifiedPagingControllerId(IdCreator.create());
  List<TItem> get items {
    final pages = pager.value.pages;
    if (pages == null) return [];
    return pages.expand((final page) => page).toList();
  }

  final _itemsCountListeners = <ValueChanged<int>>{};
  var _lastItemsCount = 0;

  PagingControllerRequestsBuilder<TItem> get requestBuilder;

  void onLoad() => loadFirstPage();

  /// ********************************************
  /// *      PAGER LISTENERS START
  /// ********************************************
  void _onPagerChanged() {
    final newCount = items.length;
    if (newCount != _lastItemsCount) {
      _lastItemsCount = newCount;
      _itemsCountListeners.forEach(_onItemsCountChanged);
    }
  }

  void _onItemsCountChanged(final ValueChanged<int> listener) {
    listener(_lastItemsCount);
  }

  /// will be triggered when count changes
  void addItemsCountListener(final ValueChanged<int> listener) {
    _itemsCountListeners.add(listener);
  }

  void removeItemsCountListener(final ValueChanged<int> listener) {
    _itemsCountListeners.remove(listener);
  }

  /// ********************************************
  /// *      PAGER LISTENERS END
  /// ********************************************

  Future<List<TItem>> _fetchPage(final int pageKey) async {
    final response = await requestBuilder.onLoadData(pageKey);
    final values = [...response.values];

    if (pageKey == _firstPageKey && addEmptyFirstItem) {
      values.insert(0, emptyItemBuilder!());
    }

    if (response.currentPage < pageKey) {
      return [];
    }

    // Update hasNextPage based on whether we've reached the last page
    final hasNextPage =
        response.pagesCount > 0 && response.currentPage < response.pagesCount;

    // Store whether this is the last page for use in the controller
    _isLastPage = !hasNextPage;

    return values;
  }

  bool _isLastPage = false;

  void loadFirstPage() => pager.fetchNextPage();
  void refresh() {
    _isLastPage = false;
    pager.refresh();
  }

  void refreshWithoutNotify() {
    _isLastPage = false;
    pager.refreshWithoutNotify();
  }

  void insertItem(final TItem item, {final int at = 0}) =>
      pager.insertElements([item], at: at);
  void insertItems(final List<TItem> items, {final int at = 0}) =>
      pager.insertElements(items, at: at);
  void moveElementFirst({
    required final TItem element,
    final bool shouldAddOnNotFound = false,
  }) {
    final index = items.indexWhere((final e) => e == element);
    if (index >= 0) {
      moveElementByIndex(element: element, index: index);
    } else if (shouldAddOnNotFound) {
      insertItem(element);
    }
  }

  /// removes element from listing at given [index], then reinserts it
  /// at [moveToIndex]
  void moveElementByIndex({
    required final int index,
    required final TItem element,

    /// target index after element removal
    final int moveToIndex = 0,
  }) => pager.moveElementByIndex(
    element: element,
    newIndex: moveToIndex,
    oldIndex: index,
  );
  void replaceItem(
    final TItem item, {
    final bool shouldAddOnNotFound = false,
    final bool Function(TItem a, TItem b)? equals,
    final int? index,
  }) => pager.replaceElement(
    element: item,
    shouldAddOnNotFound: shouldAddOnNotFound,
    equals: equals,
    index: index,
  );

  void deleteItem(final TItem item) => pager.removeElement(element: item);
  TItem? deleteItemWhere(final bool Function(TItem element) test) =>
      pager.removeElementWhere(test: test);
  Iterable<TItem> deleteItemsWhere(final bool Function(TItem element) test) =>
      pager.removeElementsWhere(test: test);
  void deleteItems(final List<TItem> items) => items.forEach(deleteItem);
  ({TItem? item, int index}) getItem(final bool Function(TItem) test) {
    final index = items.indexWhere(test);
    if (index < 0) return (index: index, item: null);
    return (index: index, item: items[index]);
  }

  @override
  void dispose() {
    _itemsCountListeners.clear();
    pager
      ..removeListener(_onPagerChanged)
      ..dispose();
  }
}
