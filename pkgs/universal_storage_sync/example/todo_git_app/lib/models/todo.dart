import 'package:from_json_to_json/from_json_to_json.dart';

/// {@template todo_id}
/// Type-safe identifier for a Todo item.
/// {@endtemplate}
extension type const TodoId(String value) {
  /// {@macro todo_id}
  factory TodoId.fromJson(final dynamic json) => TodoId(jsonDecodeString(json));

  /// Converts to JSON representation
  String toJson() => value;

  /// Whether the ID is empty
  bool get isEmpty => value.isEmpty;

  /// Empty TodoId constant
  static const empty = TodoId('');
}

/// {@template todo}
/// Zero-cost, type-safe wrapper for Todo data.
/// Represents a todo item with all its properties.
/// {@endtemplate}
extension type const Todo(Map<String, dynamic> value) {
  /// {@macro todo}
  factory Todo.fromJson(final dynamic json) => Todo(jsonDecodeMap(json));

  /// Creates a new Todo with the given properties
  factory Todo.create({
    required TodoId id,
    required String title,
    String description = '',
    bool isCompleted = false,
    DateTime? createdAt,
    DateTime? completedAt,
    List<String> tags = const [],
  }) => Todo({
    'id': id.value,
    'title': title,
    'description': description,
    'isCompleted': isCompleted,
    'createdAt': (createdAt ?? DateTime.now()).toIso8601String(),
    'completedAt': completedAt?.toIso8601String(),
    'tags': tags,
  });

  /// Todo ID
  TodoId get id => TodoId.fromJson(value['id']);

  /// Todo title
  String get title => jsonDecodeString(value['title']);

  /// Todo description
  String get description => jsonDecodeString(value['description']);

  /// Whether the todo is completed
  bool get isCompleted => jsonDecodeBool(value['isCompleted']);

  /// Creation timestamp
  DateTime get createdAt =>
      dateTimeFromIso8601String(jsonDecodeString(value['createdAt'])) ??
      DateTime.now();

  /// Completion timestamp (null if not completed)
  DateTime? get completedAt =>
      dateTimeFromIso8601String(jsonDecodeString(value['completedAt']));

  /// Associated tags
  List<String> get tags => jsonDecodeListAs<String>(value['tags']);

  /// Creates a copy of this Todo with updated properties
  Todo copyWith({
    TodoId? id,
    String? title,
    String? description,
    bool? isCompleted,
    DateTime? createdAt,
    DateTime? completedAt,
    List<String>? tags,
  }) => Todo({
    'id': (id ?? this.id).value,
    'title': title ?? this.title,
    'description': description ?? this.description,
    'isCompleted': isCompleted ?? this.isCompleted,
    'createdAt': (createdAt ?? this.createdAt).toIso8601String(),
    'completedAt': (completedAt ?? this.completedAt)?.toIso8601String(),
    'tags': tags ?? this.tags,
  });

  /// Converts to JSON representation
  Map<String, dynamic> toJson() => value;

  /// Empty Todo constant
  static const empty = Todo({});
}
