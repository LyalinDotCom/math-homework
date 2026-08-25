import Foundation

// The exact JSON Schemas the desktop app sends to Gemini, generated from
// shared/contracts.ts via toGeminiJsonSchema (draft-07, with minItems/maxItems
// stripped because the Interactions API rejects those keywords).
enum GeminiSchemas {
    static let transcription = """
    {
      "type": "object",
      "properties": {
        "worksheetTitle": { "type": "string", "maxLength": 500 },
        "problems": {
          "type": "array",
          "items": {
            "type": "object",
            "properties": {
              "number": { "type": "string", "maxLength": 500 },
              "expression": { "type": "string", "minLength": 1, "maxLength": 500 },
              "studentAnswer": { "type": "string", "maxLength": 200 },
              "confidence": { "type": "number", "minimum": 0, "maximum": 1 }
            },
            "required": ["number", "expression", "studentAnswer", "confidence"],
            "additionalProperties": false
          }
        }
      },
      "required": ["worksheetTitle", "problems"],
      "additionalProperties": false
    }
    """

    static let verification = """
    {
      "type": "object",
      "properties": {
        "problems": {
          "type": "array",
          "items": {
            "type": "object",
            "properties": {
              "index": { "type": "integer", "minimum": 0, "maximum": 499 },
              "studentAnswer": { "type": "string", "maxLength": 200 },
              "confidence": { "type": "number", "minimum": 0, "maximum": 1 },
              "needsConfirmation": { "type": "boolean" },
              "verificationNote": { "type": "string", "maxLength": 500 }
            },
            "required": [
              "index", "studentAnswer", "confidence", "needsConfirmation", "verificationNote"
            ],
            "additionalProperties": false
          }
        }
      },
      "required": ["problems"],
      "additionalProperties": false
    }
    """

    static func parsed(_ schema: String) -> [String: Any] {
        guard let data = schema.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            assertionFailure("Embedded schema is not valid JSON")
            return [:]
        }
        return object
    }
}
