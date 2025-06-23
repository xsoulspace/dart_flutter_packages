import 'package:flutter_test/flutter_test.dart';
import 'package:todo_app/models/todo.dart';

void main() {
  group('TodoId', () {
    test('creates TodoId from string', () {
      const id = TodoId('test-id');
      expect(id.value, equals('test-id'));
    });

    test('fromJson creates TodoId correctly', () {
      final id = TodoId.fromJson('test-id');
      expect(id.value, equals('test-id'));
    });

    test('toJson returns string value', () {
      const id = TodoId('test-id');
      expect(id.toJson(), equals('test-id'));
    });

    test('isEmpty returns true for empty string', () {
      const id = TodoId('');
      expect(id.isEmpty, isTrue);
    });

    test('isEmpty returns false for non-empty string', () {
      const id = TodoId('test-id');
      expect(id.isEmpty, isFalse);
    });

    test('empty constant is empty', () {
      expect(TodoId.empty.isEmpty, isTrue);
      expect(TodoId.empty.value, equals(''));
    });
  });

  group('Todo', () {
    final sampleData = {
      'id': 'test-id',
      'title': 'Test Todo',
      'description': 'This is a test todo',
      'isCompleted': false,
      'createdAt': '2023-01-01T10:00:00.000Z',
      'completedAt': null,
      'tags': ['test', 'demo'],
    };

    test('creates Todo from map', () {
      final todo = Todo(sampleData);
      expect(todo.id.value, equals('test-id'));
      expect(todo.title, equals('Test Todo'));
      expect(todo.description, equals('This is a test todo'));
      expect(todo.isCompleted, isFalse);
      expect(todo.tags, equals(['test', 'demo']));
    });

    test('fromJson creates Todo correctly', () {
      final todo = Todo.fromJson(sampleData);
      expect(todo.id.value, equals('test-id'));
      expect(todo.title, equals('Test Todo'));
    });

    test('Todo.create factory creates todo with defaults', () {
      final todo = Todo.create(
        id: const TodoId('new-id'),
        title: 'New Todo',
      );

      expect(todo.id.value, equals('new-id'));
      expect(todo.title, equals('New Todo'));
      expect(todo.description, equals(''));
      expect(todo.isCompleted, isFalse);
      expect(todo.tags, isEmpty);
      expect(todo.completedAt, isNull);
    });

    test('Todo.create factory respects provided values', () {
      final createdAt = DateTime(2023, 1, 1);
      final completedAt = DateTime(2023, 1, 2);
      final todo = Todo.create(
        id: const TodoId('custom-id'),
        title: 'Custom Todo',
        description: 'Custom description',
        isCompleted: true,
        createdAt: createdAt,
        completedAt: completedAt,
        tags: ['custom', 'test'],
      );

      expect(todo.id.value, equals('custom-id'));
      expect(todo.title, equals('Custom Todo'));
      expect(todo.description, equals('Custom description'));
      expect(todo.isCompleted, isTrue);
      expect(todo.createdAt, equals(createdAt));
      expect(todo.completedAt, equals(completedAt));
      expect(todo.tags, equals(['custom', 'test']));
    });

    test('copyWith creates new todo with updated values', () {
      final original = Todo.create(
        id: const TodoId('original-id'),
        title: 'Original Title',
        description: 'Original Description',
        tags: ['original'],
      );

      final completedAt = DateTime.now();
      final updated = original.copyWith(
        title: 'Updated Title',
        isCompleted: true,
        completedAt: completedAt,
        tags: ['updated'],
      );

      expect(updated.id.value, equals('original-id'));
      expect(updated.title, equals('Updated Title'));
      expect(updated.description, equals('Original Description'));
      expect(updated.isCompleted, isTrue);
      expect(updated.tags, equals(['updated']));
      expect(updated.completedAt, equals(completedAt));
    });

    test('copyWith preserves original values when not updated', () {
      final original = Todo.create(
        id: const TodoId('original-id'),
        title: 'Original Title',
        description: 'Original Description',
      );

      final updated = original.copyWith(isCompleted: true);

      expect(updated.id.value, equals('original-id'));
      expect(updated.title, equals('Original Title'));
      expect(updated.description, equals('Original Description'));
      expect(updated.isCompleted, isTrue);
    });

    test('toJson returns correct map', () {
      final todo = Todo.create(
        id: const TodoId('json-id'),
        title: 'JSON Todo',
        description: 'JSON Description',
        tags: ['json', 'test'],
      );

      final json = todo.toJson();
      expect(json['id'], equals('json-id'));
      expect(json['title'], equals('JSON Todo'));
      expect(json['description'], equals('JSON Description'));
      expect(json['isCompleted'], isFalse);
      expect(json['tags'], equals(['json', 'test']));
      expect(json['createdAt'], isA<String>());
    });

    test('empty constant has empty values', () {
      expect(Todo.empty.id, equals(TodoId.empty));
      expect(Todo.empty.title, equals(''));
      expect(Todo.empty.description, equals(''));
      expect(Todo.empty.isCompleted, isFalse);
      expect(Todo.empty.tags, isEmpty);
    });
  });
}
