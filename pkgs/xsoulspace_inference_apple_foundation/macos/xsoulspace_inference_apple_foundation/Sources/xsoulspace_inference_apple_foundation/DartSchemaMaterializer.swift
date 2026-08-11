import Foundation
import FoundationModels

public struct GuideDescription: Codable, Sendable {
    public let kind: String  // "description" | "range" | "count" | "pattern"
    public let text: String?  // for "description"
    public let min: Double?  // for "range"
    public let max: Double?  // for "range"
    public let count: Int?  // for "count"
    public let pattern: String?  // for "pattern"
}

// Internal representation that matches the Dart JSON shape
public final class SchemaDescription: Codable, Sendable {
    public enum Kind: String, Codable {
        case object, anyOf, enum_, array, reference, null, primitive
    }

    public let kind: Kind
    public let name: String?
    public let description: String?
    public let properties: [PropertyDescription]?
    public let choices: [SchemaDescription]?  // anyOf
    public let cases: [String]?  // enum
    public let item: SchemaDescription?  // array
    public let minItems: Int?
    public let maxItems: Int?
    public let referenceName: String?
    public let primitiveType: String?  // "String", "Int", ...
    public let guides: [GuideDescription]?
    public let representNilExplicitly: Bool?
}

public final class PropertyDescription: Codable, Sendable {
    public let name: String
    public let description: String?
    public let schema: SchemaDescription
    public let isOptional: Bool
}

///```swift
/// let generationSchema = try SchemaMaterializer.makeGenerationSchema(
///   root: dartRoot,
///   dependencies: dartDependencies
/// )
///
/// let session = LanguageModelSession(...)
/// let response = try await session.respond(generating: generationSchema) {
///   "Generate a character that orders a coffee."
/// }
///```
//extension SchemaMaterializer {
//  /// Turns the Dart-serialized tree into real DynamicGenerationSchema values.
//  public static func materialize(
//    root: String,
//    dependencies: [String]
//  ) throws -> (
//    root: DynamicGenerationSchema, dependencies: [DynamicGenerationSchema]
//  ) {
//
//    DynamicGenerationSchema(
//      root: SchemaMaterializer.build(root),
//      dependencies: dependencies.lazy.map(SchemaMaterializer.build)
//    )
//  }
//  static func build(_ desc: SchemaDescription) throws
//    -> DynamicGenerationSchema
//  {
//    switch desc.kind {
//    case .object:
//      return DynamicGenerationSchema(
//        name: desc.name!,
//        description: desc.description,
//        representNilExplicitlyInGeneratedContent: desc
//          .representNilExplicitly ?? false,
//        properties: try desc.properties!.map { prop in
//          DynamicGenerationSchema.Property(
//            name: prop.name,
//            description: prop.description,
//            schema: try build(prop.schema),
//            isOptional: prop.isOptional
//          )
//        }
//      )
//
//    case .anyOf:
//      return DynamicGenerationSchema(
//        name: desc.name!,
//        description: desc.description,
//        anyOf: try desc.choices!.map(build)
//      )
//
//    case .enum_:
//      return DynamicGenerationSchema(
//        name: desc.name!,
//        description: desc.description,
//        anyOf: desc.cases!
//      )
//
//    case .array:
//      return DynamicGenerationSchema(
//        arrayOf: try build(desc.item!),
//        minimumElements: desc.minItems,
//        maximumElements: desc.maxItems
//      )
//
//    case .reference:
//      return DynamicGenerationSchema(referenceTo: desc.referenceName!)
//
//    case .null:
//      return .null
//
//    // Map to DynamicGenerationSchema(type:guides:)
//    // + apply guides
//    case .primitive:
//      guard let typeName = desc.primitiveType else {
//        throw SchemaError("primitiveType")
//      }
//
//      let guides = try (desc.guides ?? []).map(Self.buildGuide)
//
//      switch typeName {
//      case "String":
//        return DynamicGenerationSchema(
//          type: String.self,
//          guides: guides as! [GenerationGuide<String>]
//        )
//      case "Int":
//        return DynamicGenerationSchema(
//          type: Int.self,
//          guides: guides as! [GenerationGuide<Int>]
//        )
//      case "Double":
//        return DynamicGenerationSchema(
//          type: Double.self,
//          guides: guides as! [GenerationGuide<Double>]
//        )
//      case "Bool":
//        return DynamicGenerationSchema(
//          type: Bool.self,
//          guides: guides as! [GenerationGuide<Bool>]
//        )
//      default:
//        throw SchemaError(typeName)
//      }
//    }
//  }
//  private static func buildGuide(_ desc: GuideDescription) throws
//    -> GenerationGuide
//  {
//    switch desc.kind {
//    case "description":
//      return GenerationGuide(desc.text!)
//    case "range":
//      // GenerationGuide.range is generic; the cast happens at the call site
//      return GenerationGuide.range(desc.min!...desc.max!)
//    case "count":
//      return GenerationGuide.count(desc.count!)
//    case "pattern":
//      return GenerationGuide.pattern(desc.pattern!)
//    default:
//      throw SchemaError(desc.kind)
//    }
//  }
//}

func materializeFromDartJSON(_ json: [String: Any]) throws -> GenerationSchema {
    // 1. Convert the Dictionary into Data so Codable can work
    let data = try JSONSerialization.data(withJSONObject: json)

    // 2. Decode into a simple container
    let bundle = try JSONDecoder().decode(
        SchemaBundleDescription.self,
        from: data
    )

    // 3. Call the materializer
    return try SchemaMaterializer.makeGenerationSchema(
        root: bundle.root,
        dependencies: bundle.dependencies
    )
}

// Small helper that matches the JSON keys coming from Dart
private struct SchemaBundleDescription: Codable {
    let root: SchemaDescription
    let dependencies: [SchemaDescription]
}
enum SchemaMaterializerError: Error, LocalizedError {
    case missingField(String)
    case unsupportedPrimitive(String)
    case unknownGuide(String)
    case invalidGuidePayload(String)
    case appleSchemaError(Error)

    var errorDescription: String? {
        switch self {
        case .missingField(let f): return "Missing required field: \(f)"
        case .unsupportedPrimitive(let t):
            return "Unsupported primitive type: \(t)"
        case .unknownGuide(let k): return "Unknown guide kind: \(k)"
        case .invalidGuidePayload(let m): return "Invalid guide payload: \(m)"
        case .appleSchemaError(let e):
            return "GenerationSchema error: \(e.localizedDescription)"
        }
    }
}

enum SchemaMaterializer {

    /// Builds the root + dependency `DynamicGenerationSchema` values.
    static func materialize(
        root: SchemaDescription,
        dependencies: [SchemaDescription]
    ) throws -> (
        root: DynamicGenerationSchema, dependencies: [DynamicGenerationSchema]
    ) {
        let builtRoot = try build(root)
        let builtDependencies = try dependencies.map { try build($0) }
        return (builtRoot, builtDependencies)
    }

    /// Convenience: produces a ready-to-use `GenerationSchema`.
    static func makeGenerationSchema(
        root: SchemaDescription,
        dependencies: [SchemaDescription] = []
    ) throws -> GenerationSchema {
        let (builtRoot, builtDeps) = try materialize(
            root: root,
            dependencies: dependencies
        )
        do {
            return try GenerationSchema(
                root: builtRoot,
                dependencies: builtDeps
            )
        } catch {
            throw SchemaMaterializerError.appleSchemaError(error)
        }
    }

    // MARK: - Core recursive builder

    private static func build(_ desc: SchemaDescription) throws
        -> DynamicGenerationSchema
    {
        switch desc.kind {

        // ─────────────────────────────────────────────
        // Object
        // ─────────────────────────────────────────────
        case .object:
            guard let name = desc.name else {
                throw SchemaMaterializerError.missingField("name")
            }
            let props = try (desc.properties ?? []).map {
                prop -> DynamicGenerationSchema.Property in
                DynamicGenerationSchema.Property(
                    name: prop.name,
                    description: prop.description,
                    schema: try build(prop.schema),
                    isOptional: prop.isOptional
                )
            }

            if let explicitNil = desc.representNilExplicitly {
                return DynamicGenerationSchema(
                    name: name,
                    description: desc.description,
                    representNilExplicitlyInGeneratedContent: explicitNil,
                    properties: props
                )
            } else {
                return DynamicGenerationSchema(
                    name: name,
                    description: desc.description,
                    properties: props
                )
            }

        // ─────────────────────────────────────────────
        // anyOf (union of schemas) or Enum (anyOf of strings)
        // ─────────────────────────────────────────────
        case .anyOf:
            guard let name = desc.name else {
                throw SchemaMaterializerError.missingField("name")
            }
            if let schemaChoices = desc.choices, !schemaChoices.isEmpty {
                let built = try schemaChoices.map { try build($0) }
                return DynamicGenerationSchema(
                    name: name,
                    description: desc.description,
                    anyOf: built
                )
            } else {
                // Fall through to enum-style if only string cases were sent
                fallthrough
            }

        case .enum_:
            guard let name = desc.name else {
                throw SchemaMaterializerError.missingField("name")
            }
            guard let cases = desc.cases else {
                throw SchemaMaterializerError.missingField("cases")
            }
            return DynamicGenerationSchema(
                name: name,
                description: desc.description,
                anyOf: cases
            )

        // ─────────────────────────────────────────────
        // Array
        // ─────────────────────────────────────────────
        case .array:
            guard let itemDesc = desc.item else {
                throw SchemaMaterializerError.missingField("item")
            }
            let itemSchema = try build(itemDesc)
            return DynamicGenerationSchema(
                arrayOf: itemSchema,
                minimumElements: desc.minItems,
                maximumElements: desc.maxItems
            )

        // ─────────────────────────────────────────────
        // Reference
        // ─────────────────────────────────────────────
        case .reference:
            guard let refName = desc.referenceName else {
                throw SchemaMaterializerError.missingField("referenceName")
            }
            return DynamicGenerationSchema(referenceTo: refName)

        // ─────────────────────────────────────────────
        // Null
        // ─────────────────────────────────────────────
        case .null:
            return .null

        // ─────────────────────────────────────────────
        // Primitive + Guides
        // ─────────────────────────────────────────────
        case .primitive:
            guard let typeName = desc.primitiveType else {
                throw SchemaMaterializerError.missingField("primitiveType")
            }
            return try buildPrimitive(
                typeName: typeName,
                guides: desc.guides ?? []
            )
        }
    }

    // MARK: - Primitive + Guide mapping

    private static func buildPrimitive(
        typeName: String,
        guides: [GuideDescription]
    ) throws -> DynamicGenerationSchema {
        switch typeName {
        case "String":
            let mapped: [GenerationGuide<String>] = try guides.map {
                try mapGuide($0)
            }
            return DynamicGenerationSchema(type: String.self, guides: mapped)

        case "Int":
            let mapped: [GenerationGuide<Int>] = try guides.map {
                try mapGuide($0)
            }
            return DynamicGenerationSchema(type: Int.self, guides: mapped)

        case "Double":
            let mapped: [GenerationGuide<Double>] = try guides.map {
                try mapGuide($0)
            }
            return DynamicGenerationSchema(type: Double.self, guides: mapped)

        case "Bool":
            // Bool currently accepts very few guides; we still accept the array
            let mapped: [GenerationGuide<Bool>] = try guides.map {
                try mapGuide($0)
            }
            return DynamicGenerationSchema(type: Bool.self, guides: mapped)

        default:
            throw SchemaMaterializerError.unsupportedPrimitive(typeName)
        }
    }

    /// Maps our wire-format guide into a real `GenerationGuide<Value>`.
    /// Uses a generic helper so the same code works for String/Int/Double/Bool.
    private static func mapGuide<Value>(_ desc: GuideDescription) throws
        -> GenerationGuide<Value>
    {
        switch desc.kind {
        case "constant":
            guard let text = desc.text else {
                throw SchemaMaterializerError.invalidGuidePayload(
                    "description requires text"
                )
            }
            // since Guide.description only available via the macro surface,
            // we should prefer only DynamicGenerationSchema.Property
            return GenerationGuide.constant(text) as! GenerationGuide<Value>

        case "range":
            guard let min = desc.min, let max = desc.max else {
                throw SchemaMaterializerError.invalidGuidePayload(
                    "range requires min and max"
                )
            }
            // Range is most commonly used with numeric types
            return GenerationGuide.range(min...max) as! GenerationGuide<Value>

        case "count":
            guard let count = desc.count else {
                throw SchemaMaterializerError.invalidGuidePayload(
                    "count requires count"
                )
            }
            return GenerationGuide.count(count) as! GenerationGuide<Value>

        case "pattern":
            guard let pattern = desc.pattern else {
                throw SchemaMaterializerError.invalidGuidePayload(
                    "pattern requires pattern"
                )
            }
            // pattern is String-only
            return try GenerationGuide.pattern(Regex(pattern))
                as! GenerationGuide<Value>

        default:
            throw SchemaMaterializerError.unknownGuide(desc.kind)
        }
    }
}
