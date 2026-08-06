import FoundationModels

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
public enum SchemaMaterializer {

  /// Turns the Dart-serialized tree into real DynamicGenerationSchema values.
  public static func materialize(
    root: SchemaDescription,
    dependencies: [SchemaDescription]
  ) throws -> (root: DynamicGenerationSchema, dependencies: [DynamicGenerationSchema])

  /// Convenience: directly produce a GenerationSchema ready for the model.
  public static func makeGenerationSchema(
    root: SchemaDescription,
    dependencies: [SchemaDescription] = []
  ) throws -> GenerationSchema
}

// Internal representation that matches the Dart JSON shape
public struct SchemaDescription: Codable, Sendable {
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

public struct PropertyDescription: Codable, Sendable {
  public let name: String
  public let description: String?
  public let schema: SchemaDescription
  public let isOptional: Bool
}

extension SchemaMaterializer {
  static func build(_ desc: SchemaDescription) throws -> DynamicGenerationSchema {
    switch desc.kind {
    case .object:
      return DynamicGenerationSchema(
        name: desc.name!,
        description: desc.description,
        representNilExplicitlyInGeneratedContent: desc.representNilExplicitly ?? false,
        properties: try desc.properties!.map { prop in
          DynamicGenerationSchema.Property(
            name: prop.name,
            description: prop.description,
            schema: try build(prop.schema),
            isOptional: prop.isOptional
          )
        }
      )

    case .anyOf:
      return DynamicGenerationSchema(
        name: desc.name!,
        description: desc.description,
        anyOf: try desc.choices!.map(build)
      )

    case .enum:
      return DynamicGenerationSchema(
        name: desc.name!,
        description: desc.description,
        anyOf: desc.cases!
      )

    case .array:
      return DynamicGenerationSchema(
        arrayOf: try build(desc.item!),
        minimumElements: desc.minItems,
        maximumElements: desc.maxItems
      )

    case .reference:
      return DynamicGenerationSchema(referenceTo: desc.referenceName!)

    case .null:
      return .null

    // Map to DynamicGenerationSchema(type:guides:)
    // + apply guides
    case .primitive:
      guard let typeName = desc.primitiveType else {
        throw SchemaError.missingField("primitiveType")
      }

      let guides = try (desc.guides ?? []).map(Self.buildGuide)

      switch typeName {
      case "String":
        return DynamicGenerationSchema(
          type: String.self,
          guides: guides as! [GenerationGuide<String>]
        )
      case "Int":
        return DynamicGenerationSchema(
          type: Int.self,
          guides: guides as! [GenerationGuide<Int>]
        )
      case "Double":
        return DynamicGenerationSchema(
          type: Double.self,
          guides: guides as! [GenerationGuide<Double>]
        )
      case "Bool":
        return DynamicGenerationSchema(
          type: Bool.self,
          guides: guides as! [GenerationGuide<Bool>]
        )
      default:
        throw SchemaError.unsupportedPrimitive(typeName)
      }
    }
  }
  private static func buildGuide(_ desc: GuideDescription) throws -> Any {
    switch desc.kind {
    case "description":
      return GenerationGuide.description(desc.text!)
    case "range":
      // GenerationGuide.range is generic; the cast happens at the call site
      return GenerationGuide.range(desc.min!...desc.max!)
    case "count":
      return GenerationGuide.count(desc.count!)
    case "pattern":
      return GenerationGuide.pattern(desc.pattern!)
    default:
      throw SchemaError.unknownGuide(desc.kind)
    }
  }

  ///```swift
  ///    // 1. Decode from the JSON that arrived from Dart
  /// let guideDescs = try JSONDecoder().decode([GuideDescription].self, from: data)
  ///
  /// // 2. Convert each one into a real GenerationGuide
  /// let guides = try guideDescs.map { desc in
  ///   switch desc.kind {
  ///   case "description":
  ///     return GenerationGuide.description(desc.text!)
  ///   case "range":
  ///     return GenerationGuide.range(desc.min!...desc.max!)
  ///   case "count":
  ///     return GenerationGuide.count(desc.count!)
  ///   case "pattern":
  ///     return GenerationGuide.pattern(desc.pattern!)
  ///   default:
  ///     throw SchemaError.unknownGuide(desc.kind)
  ///   }
  /// }
  /// ```
  struct GuideDescription: Codable, Sendable {
    let kind: String

    // Only some of these will be present, depending on `kind`
    let text: String?  // for "description"
    let min: Double?  // for "range"
    let max: Double?  // for "range"
    let count: Int?  // for "count"
    let pattern: String?  // for "pattern"
  }
}
