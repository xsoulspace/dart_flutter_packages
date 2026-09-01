export 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart' show ToolDef, ToolName, ToolRegistry;

export 'tool_call_parser.dart';

// fs_tools.dart is deliberately excluded: it imports dart:io and must not
// leak into web-compilable import chains. Import it directly on VM targets.
