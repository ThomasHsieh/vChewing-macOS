// (c) 2021 and onwards The vChewing Project (MIT-NTL License).
// ====================
// This code is released under the MIT license (SPDX-License-Identifier: MIT)
// ... with NTL restriction stating that:
// No trademark license is granted to use the trade names, trademarks, service
// marks, or product names of Contributor, except as required to fulfill notice
// requirements defined in MIT License.

// NOTE: API key is stored in UserDefaults for the PoC. For production, migrate
// to Keychain (SecItemAdd / SecItemCopyMatching, service "com.thomas.vChewing.cloudAPIKey").

#if canImport(Darwin)
import Foundation

// MARK: - CloudAPIEngine

nonisolated final class CloudAPIEngine: AICorrectorEngine {
  enum Provider: String {
    case anthropic
    case gemini
    case openai
    case ollama
  }

  private let provider: Provider
  private let apiKey: String

  init(provider: String, apiKey: String) {
    self.provider = Provider(rawValue: provider) ?? .anthropic
    self.apiKey = apiKey
  }

  nonisolated func correctSpelling(text: String) async -> CorrectionResult? {
    switch provider {
    case .ollama: return await callOllama(text: text)
    default:
      guard !apiKey.isEmpty else { return nil }
      switch provider {
      case .anthropic: return await callAnthropic(text: text)
      case .gemini: return await callGemini(text: text)
      case .openai: return await callOpenAI(text: text)
      case .ollama: return nil
      }
    }
  }

  // MARK: - Anthropic

  private func callAnthropic(text: String) async -> CorrectionResult? {
    guard let url = URL(string: "https://api.anthropic.com/v1/messages") else { return nil }
    var req = URLRequest(url: url)
    req.httpMethod = "POST"
    req.setValue("application/json", forHTTPHeaderField: "content-type")
    req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
    req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
    let body: [String: Any] = [
      "model": "claude-haiku-4-5-20251001",
      "max_tokens": 300,
      "system": AIPromptBuilder.cscSystemPrompt,
      "messages": [["role": "user", "content": AIPromptBuilder.cscUserPrompt(for: text)]],
    ]
    req.httpBody = try? JSONSerialization.data(withJSONObject: body)
    guard let (data, response) = try? await URLSession.shared.data(for: req),
          (response as? HTTPURLResponse)?.statusCode == 200,
          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let content = obj["content"] as? [[String: Any]],
          let jsonText = content.first?["text"] as? String
    else { return nil }
    return parseCSCResponse(jsonText, original: text)
  }

  // MARK: - Gemini

  private func callGemini(text: String) async -> CorrectionResult? {
    let urlStr =
      "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=\(apiKey)"
    guard let url = URL(string: urlStr) else { return nil }
    let combined = AIPromptBuilder.cscSystemPrompt + "\n\n" + AIPromptBuilder.cscUserPrompt(for: text)
    var req = URLRequest(url: url)
    req.httpMethod = "POST"
    req.setValue("application/json", forHTTPHeaderField: "content-type")
    let body: [String: Any] = ["contents": [["parts": [["text": combined]]]]]
    req.httpBody = try? JSONSerialization.data(withJSONObject: body)
    guard let (data, response) = try? await URLSession.shared.data(for: req),
          (response as? HTTPURLResponse)?.statusCode == 200,
          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let candidates = obj["candidates"] as? [[String: Any]],
          let content = candidates.first?["content"] as? [String: Any],
          let parts = content["parts"] as? [[String: Any]],
          let jsonText = parts.first?["text"] as? String
    else { return nil }
    return parseCSCResponse(jsonText, original: text)
  }

  // MARK: - OpenAI

  private func callOpenAI(text: String) async -> CorrectionResult? {
    guard let url = URL(string: "https://api.openai.com/v1/chat/completions") else { return nil }
    var req = URLRequest(url: url)
    req.httpMethod = "POST"
    req.setValue("application/json", forHTTPHeaderField: "content-type")
    req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "authorization")
    let body: [String: Any] = [
      "model": "gpt-4o-mini",
      "max_tokens": 300,
      "messages": [
        ["role": "system", "content": AIPromptBuilder.cscSystemPrompt],
        ["role": "user", "content": AIPromptBuilder.cscUserPrompt(for: text)],
      ],
    ]
    req.httpBody = try? JSONSerialization.data(withJSONObject: body)
    guard let (data, response) = try? await URLSession.shared.data(for: req),
          (response as? HTTPURLResponse)?.statusCode == 200,
          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let choices = obj["choices"] as? [[String: Any]],
          let message = choices.first?["message"] as? [String: Any],
          let jsonText = message["content"] as? String
    else { return nil }
    return parseCSCResponse(jsonText, original: text)
  }

  // MARK: - Ollama (本機)

  private func callOllama(text: String) async -> CorrectionResult? {
    guard let url = URL(string: "http://localhost:11434/v1/chat/completions") else { return nil }
    var req = URLRequest(url: url)
    req.httpMethod = "POST"
    req.setValue("application/json", forHTTPHeaderField: "content-type")
    let body: [String: Any] = [
      "model": "qwen2.5:7b",
      "messages": [
        ["role": "system", "content": AIPromptBuilder.cscSystemPrompt],
        ["role": "user", "content": AIPromptBuilder.cscUserPrompt(for: text)],
      ],
    ]
    req.httpBody = try? JSONSerialization.data(withJSONObject: body)
    guard let (data, response) = try? await URLSession.shared.data(for: req),
          (response as? HTTPURLResponse)?.statusCode == 200,
          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let choices = obj["choices"] as? [[String: Any]],
          let message = choices.first?["message"] as? [String: Any],
          let jsonText = message["content"] as? String
    else { return nil }
    return parseCSCResponse(jsonText, original: text)
  }

  // MARK: - JSON parser

  private func parseCSCResponse(_ json: String, original: String) -> CorrectionResult? {
    let cleaned = extractJSON(from: json)
    guard let data = cleaned.data(using: .utf8),
          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          obj["corrected"] is String
    else { return nil }

    let changesRaw = obj["changes"] as? [[String: Any]] ?? []
    var corrections: [SingleCorrection] = []
    for change in changesRaw {
      guard let from = change["from"] as? String,
            let to = change["to"] as? String,
            let position = change["position"] as? Int,
            from.count == to.count,
            position >= 0, position + from.count <= original.count
      else { continue }
      // Validate 'from' matches original at given position; tolerate ±1 off-by-one from model
      func matchAt(_ pos: Int) -> Bool {
        guard pos >= 0, pos + from.count <= original.count else { return false }
        let s = original.index(original.startIndex, offsetBy: pos)
        let e = original.index(s, offsetBy: from.count)
        return String(original[s ..< e]) == from
      }
      let actualPos: Int
      if matchAt(position) { actualPos = position }
      else if matchAt(position - 1) { actualPos = position - 1 }
      else if matchAt(position + 1) { actualPos = position + 1 }
      else { continue }
      corrections.append(
        .init(charOffset: actualPos, charLength: from.count, original: from, corrected: to, reason: .homophones)
      )
    }

    // If model provided no validated changes, fall back to comparing model's corrected field char-by-char
    let modelCorrected = obj["corrected"] as? String ?? original
    if corrections.isEmpty, modelCorrected != original, modelCorrected.count == original.count {
      let origChars = Array(original)
      let corrChars = Array(modelCorrected)
      for i in origChars.indices where origChars[i] != corrChars[i] {
        corrections.append(.init(
          charOffset: i, charLength: 1,
          original: String(origChars[i]), corrected: String(corrChars[i]),
          reason: .homophones
        ))
      }
    }

    // Rebuild corrected string from validated corrections (don't trust model's `corrected` field directly)
    var rebuiltChars = Array(original)
    for c in corrections {
      let toChars = Array(c.corrected)
      guard c.charOffset + c.charLength <= rebuiltChars.count, toChars.count == c.charLength else { continue }
      rebuiltChars.replaceSubrange(c.charOffset ..< c.charOffset + c.charLength, with: toChars)
    }
    let rebuiltCorrected = String(rebuiltChars)

    let changeRatio = corrections.isEmpty
      ? 0.0
      : Double(corrections.reduce(0) { $0 + $1.charLength }) / Double(max(original.count, 1))
    let confidence = changeRatio > 0.7 ? 0.5 : 0.9

    return CorrectionResult(
      original: original, corrected: rebuiltCorrected, corrections: corrections, confidence: confidence
    )
  }

  private func extractJSON(from text: String) -> String {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if let start = trimmed.range(of: "{"), let end = trimmed.range(of: "}", options: .backwards) {
      return String(trimmed[start.lowerBound ..< end.upperBound])
    }
    return trimmed
  }
}

#endif
