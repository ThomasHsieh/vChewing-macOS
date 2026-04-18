// (c) 2021 and onwards The vChewing Project (MIT-NTL License).
// ====================
// This code is released under the MIT license (SPDX-License-Identifier: MIT)
// ... with NTL restriction stating that:
// No trademark license is granted to use the trade names, trademarks, service
// marks, or product names of Contributor, except as required to fulfill notice
// requirements defined in MIT License.

// NOTE: MLXLLM requires macOS 14+ and cannot be linked into a package that
// targets macOS 12. To enable full MLX inference:
//   1. Add `mlx-swift-examples` (exact: "2.21.2") to Package.swift dependencies.
//   2. Add MLXLLM / MLXLMCommon to target dependencies.
//   3. Raise the minimum platform to .macOS(.v14).
//   4. Replace the stub body of correctSpelling() below with the real implementation.
//
// Real implementation template (arm64 only):
//
//   #if arch(arm64)
//   import MLXLLM
//   import MLXLMCommon
//   func correctSpelling(text: String) async -> CorrectionResult? {
//     let config = ModelConfiguration(directory: modelDir)
//     let container = try? await LLMModelFactory.shared.loadContainer(configuration: config)
//     guard let container else { return nil }
//     let messages: [Message] = [
//       .init(role: .system, content: AIPromptBuilder.cscSystemPrompt),
//       .init(role: .user, content: AIPromptBuilder.cscUserPrompt(for: text)),
//     ]
//     let jsonString: String? = try? await container.perform { ctx in
//       var out = ""
//       let inp = try ctx.processor.prepare(input: .messages(messages))
//       let r = try MLXLMCommon.generate(input: inp,
//                                        parameters: .init(maxTokens: 300),
//                                        context: ctx) { _ in .more }
//       out = r.output; return out
//     }
//     return jsonString.flatMap { parseCSCResponse($0, original: text) }
//   }
//   #endif

#if canImport(Darwin)
import Foundation

// MARK: - LocalMLXEngine (stub — see note above to enable real MLX inference)

final class LocalMLXEngine: AICorrectorEngine {
  private let modelDir: URL

  init(modelSize: String) {
    let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
      .first!
    let modelName = modelSize == "large"
      ? "Qwen2.5-3B-Instruct-4bit"
      : "Qwen2.5-1.5B-Instruct-4bit"
    self.modelDir = appSupport.appendingPathComponent("vChewing/AIModels/\(modelName)")
  }

  func correctSpelling(text: String) async -> CorrectionResult? {
    // Stub: returns nil until MLXLLM is linked (see file header).
    nil
  }
}

#endif
