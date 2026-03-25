import 'dart:convert';
import 'dart:ffi';

import 'package:ffi/ffi.dart';

/// Allocator abstraction used for pointer lifecycle tests and runtime safety.
abstract interface class SteamMemoryAllocator {
  Pointer<Uint8> allocateUint8(int elementCount);

  Pointer<Int8> allocateInt8(int elementCount);

  Pointer<Int32> allocateInt32(int elementCount);

  Pointer<Float> allocateFloat(int elementCount);

  void free(Pointer<NativeType> pointer);
}

/// Production allocator backed by `calloc`.
final class SteamCallocAllocator implements SteamMemoryAllocator {
  const SteamCallocAllocator();

  @override
  Pointer<Uint8> allocateUint8(final int elementCount) =>
      calloc<Uint8>(elementCount);

  @override
  Pointer<Int8> allocateInt8(final int elementCount) =>
      calloc<Int8>(elementCount);

  @override
  Pointer<Int32> allocateInt32(final int elementCount) =>
      calloc<Int32>(elementCount);

  @override
  Pointer<Float> allocateFloat(final int elementCount) =>
      calloc<Float>(elementCount);

  @override
  void free(final Pointer<NativeType> pointer) {
    calloc.free(pointer);
  }
}

/// Arena that tracks all native allocations and frees them in one call.
final class SteamPointerArena {
  SteamPointerArena({
    final SteamMemoryAllocator allocator = const SteamCallocAllocator(),
  }) : _allocator = allocator;

  final SteamMemoryAllocator _allocator;
  final List<Pointer<NativeType>> _allocations = <Pointer<NativeType>>[];

  bool _released = false;

  Pointer<T> alloc<T extends SizedNativeType>({final int count = 1}) {
    _ensureNotReleased();
    if (T == Uint8) {
      final pointer = _allocator.allocateUint8(count).cast<T>();
      _allocations.add(pointer.cast<NativeType>());
      return pointer;
    }
    if (T == Int8) {
      final pointer = _allocator.allocateInt8(count).cast<T>();
      _allocations.add(pointer.cast<NativeType>());
      return pointer;
    }
    if (T == Int32) {
      final pointer = _allocator.allocateInt32(count).cast<T>();
      _allocations.add(pointer.cast<NativeType>());
      return pointer;
    }
    if (T == Float) {
      final pointer = _allocator.allocateFloat(count).cast<T>();
      _allocations.add(pointer.cast<NativeType>());
      return pointer;
    }

    throw UnsupportedError('Unsupported allocation type: $T');
  }

  Pointer<Int8> allocCharBuffer(final int lengthBytes) {
    if (lengthBytes <= 0) {
      throw ArgumentError.value(lengthBytes, 'lengthBytes', 'Must be > 0.');
    }
    return alloc<Int8>(count: lengthBytes);
  }

  Pointer<Utf8> allocUtf8(final String value) {
    _ensureNotReleased();
    final units = utf8.encode(value);
    final ptr = alloc<Uint8>(count: units.length + 1);
    for (var i = 0; i < units.length; i++) {
      ptr[i] = units[i];
    }
    ptr[units.length] = 0;
    return ptr.cast<Utf8>();
  }

  String readUtf8(final Pointer<Utf8> pointer) {
    if (pointer == nullptr) {
      return '';
    }
    return pointer.toDartString();
  }

  String readNullTerminated(
    final Pointer<Uint8> pointer, {
    final int maxBytes = 4096,
  }) {
    if (pointer == nullptr || maxBytes <= 0) {
      return '';
    }

    var length = 0;
    while (length < maxBytes && pointer[length] != 0) {
      length++;
    }

    if (length == 0) {
      return '';
    }

    final bytes = pointer.asTypedList(length);
    return utf8.decode(bytes, allowMalformed: true);
  }

  void releaseAll() {
    if (_released) {
      return;
    }
    _released = true;

    for (final pointer in _allocations.reversed) {
      _allocator.free(pointer);
    }
    _allocations.clear();
  }

  void _ensureNotReleased() {
    if (_released) {
      throw StateError('SteamPointerArena is already released.');
    }
  }
}
