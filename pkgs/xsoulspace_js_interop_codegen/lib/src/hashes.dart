import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

String sha256Hex(List<int> bytes) => sha256.convert(bytes).toString();

String sha512Hex(List<int> bytes) => sha512.convert(bytes).toString();

String sha512Base64(Uint8List bytes) =>
    base64Encode(sha512.convert(bytes).bytes);
