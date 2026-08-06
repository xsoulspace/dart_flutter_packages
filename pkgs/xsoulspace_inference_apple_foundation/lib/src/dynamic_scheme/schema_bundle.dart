class SchemaBundle {
  const SchemaBundle({required this.root, this.dependencies = const []});

  final Schema root;
  final List<Schema> dependencies;

  Map<String, dynamic> toJson() => {
    'root': schemaToJson(root),
    'dependencies': dependencies.map(schemaToJson).toList(),
  };

  factory SchemaBundle.fromJson(Map<String, dynamic> json) {
    return SchemaBundle(
      root: schemaFromJson(json['root'] as Map<String, dynamic>),
      dependencies: (json['dependencies'] as List<dynamic>)
          .map((e) => schemaFromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}
