// (c) 2021 and onwards The vChewing Project (MIT-NTL License).
// ====================
// This code is released under the MIT license (SPDX-License-Identifier: MIT)
// ... with NTL restriction stating that:
// No trademark license is granted to use the trade names, trademarks, service
// marks, or product names of Contributor, except as required to fulfill notice
// requirements defined in MIT License.

#if canImport(Darwin)

nonisolated enum AIPromptBuilder {
  nonisolated static let cscSystemPrompt = """
    你是一個繁體中文注音輸入法的同音字修正助手。
    使用者透過注音輸入法輸入了一段文字，可能含有同音字或近似音字錯誤（例如「在」打成「再」）。
    請只修正注音讀音相同或相近的用字錯誤，使文意更合理。

    嚴格規則：
    1. 修正後的字數必須與原文完全相同，不可增加或刪除任何字
    2. 只修正注音讀音相同（同音字）或相近（近音字）的錯誤，不可修改文意或措辭
    3. 每個修正的 from 和 to 字數必須相同
    4. 若整句文意已合理，請原文回傳，changes 為空陣列
    5. 回傳格式為 JSON：{"corrected": "修正後文字", "changes": [{"from": "原字或詞", "to": "修正字或詞", "position": 位置}]}
    6. position 從 0 開始，以字元為單位
    7. 不要加任何說明，只回傳 JSON
    """

  nonisolated static func cscUserPrompt(for text: String) -> String {
    "輸入文字：\(text)"
  }

  nonisolated static let rewriteSystemPrompt = """
    你是一個繁體中文寫作助手。
    使用者輸入了一段文字，請評估是否有更自然、更通順的說法。

    規則：
    1. 只在原文有明顯改善空間時才給建議，否則回傳 null
    2. 建議的改寫應保持原意，不添加或刪除資訊
    3. 回傳格式為 JSON：{"suggestion": "改寫後文字"} 或 {"suggestion": null}
    4. 不要加任何說明，只回傳 JSON
    """

  nonisolated static func rewriteUserPrompt(for text: String) -> String {
    "原文：\(text)"
  }
}

#endif
