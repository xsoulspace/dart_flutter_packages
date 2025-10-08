# Infinite Scroll Pagination Utils

This module complements the `infinite_scroll_pagination` package (v5.1.1+) by providing a structured approach to paginated data loading with built-in hash-based deduplication and item manipulation.

## Key Components

- **PagingControllerRequestsBuilder**: Extend to define how data should be fetched for each page.
- **BasePagingController**: Base class providing automatic pagination management. Extend this to create strongly-typed controllers for your data models.
- **HashPagingController**: Extends PagingController with hash-based deduplication and additional item manipulation methods (insert, delete, move, replace).
- **PagingControllerPageModel**: Data model for paginated responses containing values, current page, and total pages count.

## How to Use

### 1. Implement PagingControllerRequestsBuilder

Define how to fetch paginated data. For example, with a `Todo` model and `TodoApi` class:

```dart
class TodoPagingControllerRequestsBuilder extends PagingControllerRequestsBuilder<Todo> {
  TodoPagingControllerRequestsBuilder({
    required super.onLoadData,
  });

  factory TodoPagingControllerRequestsBuilder.mockRequest() =>
    TodoPagingControllerRequestsBuilder(
      onLoadData: (final pageKey) async => PagingControllerPageModel(
        values: [Todo(id: '1', title: 'Todo 1', description: 'Description 1')],
        currentPage: 1,
        pagesCount: 1,
      ),
    );

  factory TodoPagingControllerRequestsBuilder.allTodos({
    required TodoApi todoApi,
  }) => TodoPagingControllerRequestsBuilder(
    onLoadData: (final pageKey) async => todoApi.getPaginatedTodos(pageKey),
  );
}
```

### 2. Extend BasePagingController

Create a strongly-typed controller for your data model:

```dart
class TodoPagingController extends BasePagingController<Todo> {
  TodoPagingController({
    required this.requestBuilder,
  });
  @override
  final TodoPagingControllerRequestsBuilder requestBuilder;
}
```

### 3. Use your favorite Dependency Injection

Integrate with any Dependency Injection solution (Provider, InheritedWidget, GetIt, etc.):

```dart
class TodosNotifier with ChangeNotifier {
  TodosNotifier({
    required this.todoApi,
  });
  final TodoApi todoApi;
  late final todoPagingController = TodoPagingController(
    requestBuilder: TodoPagingControllerRequestsBuilder.allTodos(todoApi: todoApi),
  );

  /// Initialize the controller and load the first page.
  void onLoad() {
    todoPagingController.onLoad();
  }

  /// Refresh data and reload from the first page.
  void reload() {
    todoPagingController.refresh();
  }

  @override
  void dispose() {
    todoPagingController.dispose();
    super.dispose();
  }
}
```

## Available Methods

### BasePagingController

- `onLoad()` - Initialize and load the first page
- `loadFirstPage()` - Manually trigger loading of the first page
- `refresh()` - Reset and reload from the first page
- `refreshWithoutNotify()` - Reset state without notifying listeners
- `insertItem(item, {at})` - Insert item at specified position
- `insertItems(items, {at})` - Insert multiple items at specified position
- `deleteItem(item)` - Remove a specific item
- `deleteItemWhere(test)` - Remove first item matching the test
- `deleteItemsWhere(test)` - Remove all items matching the test
- `replaceItem(item, {equals, index})` - Replace an existing item
- `moveElementFirst(element, {shouldAddOnNotFound})` - Move element to first position
- `addItemsCountListener(listener)` - Listen to item count changes
- `removeItemsCountListener(listener)` - Remove item count listener

### HashPagingController

All BasePagingController methods plus hash-based deduplication automatically applied during pagination.
