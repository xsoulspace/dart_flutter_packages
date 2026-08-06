// lib/builder.dart
import 'package:build/build.dart';
import 'package:source_gen/source_gen.dart';

import 'generator.dart';

Builder generableBuilder(BuilderOptions options) => LibraryBuilder(
  GenerableGenerator(),
  generatedExtension: '.swift', // key point
  header: '// GENERATED CODE - DO NOT MODIFY BY HAND\n',
);
