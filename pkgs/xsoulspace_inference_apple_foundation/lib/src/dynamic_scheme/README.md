Architecture
```
Dart Schema DSL  →  SchemaDescription (serializable tree)
         ↓
   (FFI / MethodChannel / JSON)
         ↓
Swift SchemaMaterializer  →  DynamicGenerationSchema
         ↓
GenerationSchema(root:dependencies:)
```