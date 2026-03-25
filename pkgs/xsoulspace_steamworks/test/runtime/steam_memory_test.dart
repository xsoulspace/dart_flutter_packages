import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:test/test.dart';
import 'package:xsoulspace_steamworks/src/runtime/steam_memory.dart';

void main() {
  test('pointer arena frees all allocations on error path', () {
    final allocator = _CountingAllocator();
    final arena = SteamPointerArena(allocator: allocator);

    expect(() {
      try {
        arena.allocUtf8('steam');
        arena.allocCharBuffer(32);
        throw StateError('boom');
      } finally {
        arena.releaseAll();
      }
    }, throwsStateError);

    expect(allocator.allocations, 2);
    expect(allocator.frees, 2);
  });

  test('null-terminated reader decodes UTF-8 content', () {
    final arena = SteamPointerArena();
    addTearDown(arena.releaseAll);

    final ptr = arena.alloc<Uint8>(count: 6);
    ptr[0] = 'h'.codeUnitAt(0);
    ptr[1] = 'e'.codeUnitAt(0);
    ptr[2] = 'l'.codeUnitAt(0);
    ptr[3] = 'l'.codeUnitAt(0);
    ptr[4] = 'o'.codeUnitAt(0);
    ptr[5] = 0;

    expect(arena.readNullTerminated(ptr), 'hello');
  });
}

final class _CountingAllocator implements SteamMemoryAllocator {
  var allocations = 0;
  var frees = 0;

  @override
  Pointer<Uint8> allocateUint8(final int elementCount) {
    allocations++;
    return calloc<Uint8>(elementCount);
  }

  @override
  Pointer<Int8> allocateInt8(final int elementCount) {
    allocations++;
    return calloc<Int8>(elementCount);
  }

  @override
  Pointer<Int32> allocateInt32(final int elementCount) {
    allocations++;
    return calloc<Int32>(elementCount);
  }

  @override
  Pointer<Float> allocateFloat(final int elementCount) {
    allocations++;
    return calloc<Float>(elementCount);
  }

  @override
  void free(final Pointer<NativeType> pointer) {
    frees++;
    calloc.free(pointer);
  }
}
