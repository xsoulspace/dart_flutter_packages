import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';
import 'package:xsoulspace_inference_openrouter/xsoulspace_inference_openrouter.dart';
import 'dart:io';

Future<void> main() async {
  final key = Platform.environment['OPENROUTER_API_KEY']!;
  final model =
      Platform.environment['OR_MODEL'] ?? 'deepseek/deepseek-v4-flash-0731';
  final client = OpenRouterInferenceClient(apiKey: key, defaultModel: model);
  final res = await client.infer(
    InferenceRequest(
      task: InferenceTask.text,
      prompt: 'Reply with exactly: ok',
    ),
  );
  print('ok: ${res.success}');
  if (!res.success) {
    print('error: ${res.error?.code} — ${res.error?.message}');
    print('details: ${res.error?.details}');
  } else {
    print("text: ${res.data!.rawOutput ?? res.data.toString()}");
  }
  await client.dispose();
}
