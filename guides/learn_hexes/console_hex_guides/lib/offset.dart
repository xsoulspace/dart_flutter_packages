// lib/offset.dart
enum OffsetCoordType {
  oddR, // Pointy top, odd rows shifted right
  evenR, // Pointy top, even rows shifted right
  oddQ,  // Flat top, odd columns shifted down
  evenQ  // Flat top, even columns shifted down
}

class OffsetCoord {
  final int col;
  final int row;
  // final OffsetCoordType type; // We might not need to store type if conversions handle it

  OffsetCoord(this.col, this.row);

  @override
  String toString() => 'OffsetCoord($col, $row)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OffsetCoord &&
          runtimeType == other.runtimeType &&
          col == other.col &&
          row == other.row;

  @override
  int get hashCode => col.hashCode ^ row.hashCode;
}
