// (c) 2021 and onwards The vChewing Project (MIT-NTL License).
// ====================
// This code is released under the MIT license (SPDX-License-Identifier: MIT)
// ... with NTL restriction stating that:
// No trademark license is granted to use the trade names, trademarks, service
// marks, or product names of Contributor, except as required to fulfilled notice
// requirements defined in MIT License.

#if canImport(Darwin)
import Foundation
import os.log

// MARK: - InputHandler + AI Correction

private let aiLog = OSLog(subsystem: "org.atelierInmu.inputmethod.vChewing", category: "AICorrector")

extension InputHandler {
  public func postInputAIDebounce() {
    guard prefs.aiCorrectionEnabled else {
      aiDebounceWorkItem?.cancel()
      aiDebounceWorkItem = nil
      return
    }
    // If the key just committed text (Enter, Space, etc.), cancel any pending debounce
    guard session?.state.type == .ofInputting else {
      aiDebounceWorkItem?.cancel()
      aiDebounceWorkItem = nil
      return
    }

    aiDebounceWorkItem?.cancel()
    let workItem = DispatchWorkItem { [weak self] in
      self?.triggerAICorrection()
    }
    aiDebounceWorkItem = workItem
    let delayMs = max(300, min(prefs.aiDebounceMs, 2000))
    DispatchQueue.main.asyncAfter(
      deadline: DispatchTime.now() + .milliseconds(delayMs), execute: workItem
    )
  }

  private func triggerAICorrection() {
    os_log("[AI] triggerAICorrection fired", log: aiLog, type: .error)
    guard prefs.aiCorrectionEnabled, prefs.aiCSCEnabled else {
      os_log("[AI] guard: aiCorrectionEnabled or aiCSCEnabled is false", log: aiLog, type: .error)
      return
    }
    guard let session, session.state.type == .ofInputting else {
      os_log("[AI] guard: session nil or state not ofInputting", log: aiLog, type: .error)
      return
    }
    guard !smartSwitchState.isTempEnglishMode else {
      os_log("[AI] guard: isTempEnglishMode", log: aiLog, type: .error)
      return
    }

    let sentence = assembler.assembledSentence
    let preeditText = sentence.map(\.value).joined()
    os_log("[AI] preeditText=%{public}@ count=%d threshold=%d", log: aiLog, type: .error,
           preeditText, preeditText.count, prefs.aiCSCThreshold)
    guard preeditText.count >= prefs.aiCSCThreshold else {
      os_log("[AI] guard: preeditText too short", log: aiLog, type: .error)
      return
    }

    guard let engine = makeEngine() else {
      os_log("[AI] guard: makeEngine returned nil", log: aiLog, type: .error)
      return
    }
    os_log("[AI] calling engine.correctSpelling", log: aiLog, type: .error)

    Task { [weak self] in
      guard let self else { return }
      guard let result = await engine.correctSpelling(text: preeditText) else {
        os_log("[AI] correctSpelling returned nil", log: aiLog, type: .error)
        return
      }
      os_log("[AI] result: original=%{public}@ corrected=%{public}@ confidence=%f corrections=%d",
             log: aiLog, type: .error,
             result.original, result.corrected, result.confidence, result.corrections.count)
      CorrectionApplier.apply(result, to: self, prefs: self.prefs)
    }
  }

  private func makeEngine() -> (any AICorrectorEngine)? {
    let provider = prefs.aiCloudProvider
    if provider == "ollama" {
      return CloudAPIEngine(provider: provider, apiKey: "")
    }
    if prefs.aiEngineType == "cloud" {
      let key = prefs.aiCloudAPIKey
      guard !key.isEmpty else { return nil }
      return CloudAPIEngine(provider: provider, apiKey: key)
    }
    return LocalMLXEngine(modelSize: prefs.aiLocalModelSize)
  }
}

#endif
