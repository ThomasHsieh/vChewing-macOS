// (c) 2021 and onwards The vChewing Project (MIT-NTL License).
// ====================
// This code is released under the MIT license (SPDX-License-Identifier: MIT)
// ... with NTL restriction stating that:
// No trademark license is granted to use the trade names, trademarks, service
// marks, or product names of Contributor, except as required to fulfill notice
// requirements defined in MIT License.

#if canImport(Darwin)
import os.log

private let applierLog = OSLog(subsystem: "org.atelierInmu.inputmethod.vChewing", category: "AICorrector")

// MARK: - CorrectionApplier

enum CorrectionApplier {
  @MainActor
  static func apply(_ result: CorrectionResult, to handler: InputHandler, prefs: any PrefMgrProtocol) {
    os_log("[AI] apply: corrected=%{public}@ confidence=%f corrections=%d",
           log: applierLog, type: .error,
           result.corrected, result.confidence, result.corrections.count)
    guard result.corrected != result.original, !result.corrected.isEmpty else {
      os_log("[AI] apply exit: corrected == original or empty", log: applierLog, type: .error)
      return
    }
    guard result.confidence >= prefs.aiConfidenceThreshold else {
      os_log("[AI] apply exit: confidence %f < threshold %f", log: applierLog, type: .error,
             result.confidence, prefs.aiConfidenceThreshold)
      return
    }
    guard !result.corrections.isEmpty else {
      os_log("[AI] apply exit: corrections empty", log: applierLog, type: .error)
      return
    }

    let currentText = handler.assembler.assembledSentence.map(\.value).joined()
    os_log("[AI] apply: currentText=%{public}@ original=%{public}@", log: applierLog, type: .error,
           currentText, result.original)
    guard currentText == result.original else {
      os_log("[AI] apply exit: currentText != original", log: applierLog, type: .error)
      return
    }

    // SmartSwitch 有凍結段落時跳過（避免干擾中英切換流程）
    guard handler.smartSwitchState.frozenSegments.isEmpty else { return }


    // 修正後字數必須與原文相同（不能增減字數）
    guard result.corrected.count == result.original.count else { return }

    // 用 frozenSegments 機制把修正結果放進 preedit，讓使用者確認後再 Enter 遞交
    handler.smartSwitchState.clearFrozenSegments()
    handler.smartSwitchState.freezeSegment(result.corrected)
    handler.assembler.clear()
    os_log("[AI] before switchState: frozen=%{public}@", log: applierLog, type: .error,
           handler.smartSwitchState.frozenSegments.joined())
    var newState = handler.generateStateOfInputting(sansReading: false)
    newState.tooltip = "AI"
    newState.tooltipDuration = 2.0
    handler.session?.switchState(newState)
    os_log("[AI] after switchState: frozen=%{public}@", log: applierLog, type: .error,
           handler.smartSwitchState.frozenSegments.joined())
  }
}

#endif
