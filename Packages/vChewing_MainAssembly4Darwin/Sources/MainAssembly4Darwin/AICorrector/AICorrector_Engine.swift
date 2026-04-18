// (c) 2021 and onwards The vChewing Project (MIT-NTL License).
// ====================
// This code is released under the MIT license (SPDX-License-Identifier: MIT)
// ... with NTL restriction stating that:
// No trademark license is granted to use the trade names, trademarks, service
// marks, or product names of Contributor, except as required to fulfill notice
// requirements defined in MIT License.

#if canImport(Darwin)
import Foundation

// MARK: - AICorrectorEngine

public protocol AICorrectorEngine: Sendable {
  func correctSpelling(text: String) async -> CorrectionResult?
}

// MARK: - CorrectionResult

public struct CorrectionResult: Sendable {
  public let original: String
  public let corrected: String
  public let corrections: [SingleCorrection]
  public let confidence: Double

  public nonisolated init(
    original: String,
    corrected: String,
    corrections: [SingleCorrection],
    confidence: Double
  ) {
    self.original = original
    self.corrected = corrected
    self.corrections = corrections
    self.confidence = confidence
  }
}

// MARK: - SingleCorrection

public struct SingleCorrection: Sendable {
  public let charOffset: Int
  public let charLength: Int
  public let original: String
  public let corrected: String
  public let reason: CorrectionReason

  public nonisolated init(
    charOffset: Int,
    charLength: Int,
    original: String,
    corrected: String,
    reason: CorrectionReason
  ) {
    self.charOffset = charOffset
    self.charLength = charLength
    self.original = original
    self.corrected = corrected
    self.reason = reason
  }
}

// MARK: - CorrectionReason

public enum CorrectionReason: Sendable {
  case homophones
  case similarPhonetic
  case contextualMeaning
}

#endif
