// a3_ledger.dart - append one row to receipts/A3-run.jsonl via the FROZEN
// lib ledger (hash-chained jsonl; denominator journal). Never edits rows.
//
// usage: dart run a3_ledger.dart <ledger.jsonl> <kind> <payload.json>
import 'dart:convert';
import 'dart:io';

import 'package:xsoulspace_inference_weightmap/xsoulspace_inference_weightmap.dart';

void main(List<String> args) {
  if (args.length != 3) {
    stderr.writeln('usage: dart run a3_ledger.dart <ledger> <kind> <payload>');
    exit(64);
  }
  final file = File(args[0]);
  final payload =
      (jsonDecode(File(args[2]).readAsStringSync()) as Map)
          .cast<String, Object?>();
  final row = append(file, args[1], payload);
  final verdict = verifyChain(file);
  stdout.writeln('LEDGER_OK seq=${row.seq} digest=${row.digest} $verdict');
}
