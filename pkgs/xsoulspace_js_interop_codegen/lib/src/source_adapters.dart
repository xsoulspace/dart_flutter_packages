abstract interface class NpmDtsSourceAdapter {
  Future<DtsSourceResult> resolve({
    required String packageName,
    required String version,
  });
}

abstract interface class DocsExtractorSourceAdapter {
  Future<DocsSourceResult> resolve({required List<Uri> pageUrls});
}

abstract interface class RuntimeSurfaceSourceAdapter {
  Future<RuntimeSurfaceResult> resolve({required Uri scriptUrl});
}

final class DtsSourceResult {
  const DtsSourceResult({
    required this.content,
    required this.provenance,
    required this.metadata,
  });

  final String content;
  final String provenance;
  final Map<String, Object?> metadata;
}

final class DocsSourceResult {
  const DocsSourceResult({required this.pages, required this.contentHash});

  final Map<Uri, String> pages;
  final String contentHash;
}

final class RuntimeSurfaceResult {
  const RuntimeSurfaceResult({
    required this.surfaceSymbols,
    required this.version,
    required this.scriptHash,
  });

  final Set<String> surfaceSymbols;
  final String version;
  final String scriptHash;
}
