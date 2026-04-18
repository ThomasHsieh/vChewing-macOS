# FEATURE_AICorrection — AI 輔助輸入修正

**版本**：v0.1  
**日期**：2026-04-17  
**狀態**：Draft  
**作者**：Thomas Hsieh（規格）/ Claude（撰寫）

---

## 1. 功能概述

### 1.1 目標

在使用者尚未確認送出組字區內容前，透過 AI 語言模型分析組字區的顯示文字，自動修正同音字錯誤、近似音錯誤或語意不通順的用字，並選擇性地提示更自然的說法。

修正結果直接反映在組字區（preedit buffer）內，使用者若不接受修正，只需繼續用注音覆蓋或用方向鍵重新選字，天然可還原，**不需要額外的 Undo 機制**。

### 1.2 兩個子功能

| 子功能 | 說明 | 觸發閾值（預設） |
|--------|------|----------------|
| **CSC 模式**（Chinese Spelling Correction） | 修正同音字、近似音錯誤用字 | 累積 ≥ 5 字 |
| **Rewrite 模式**（語意重寫建議） | 建議更自然的完整說法 | 累積 ≥ 10 字 |

兩個子功能皆可在設定頁面獨立開關與調整閾值。

### 1.3 設計原則

- **最小侵入**：AI 修正只在使用者暫停輸入時觸發（debounce），不打斷輸入節奏
- **可忽略**：使用者若不喜歡修正結果，繼續輸入即可覆蓋，無需額外操作
- **隱私第一**：預設使用本地模型；雲端 API 為使用者自選，明確告知文字會送出
- **架構隔離**：AI 引擎跑在獨立的 XPC Service，崩潰不影響主輸入法進程

---

## 2. 觸發機制

### 2.1 觸發條件（全部滿足才觸發）

1. AI 修正功能已啟用（UserDef 開關）
2. 組字區目前的顯示文字長度 ≥ 設定閾值（預設 CSC=5字、Rewrite=10字）
3. 距離上次按鍵輸入已超過 debounce 時間（預設 800ms）
4. AI 引擎目前不在處理前一次請求中（避免重疊）
5. 目前 IMEState 為 `.ofInputting`（非候選窗、非符號表、非數字快打等狀態）

### 2.2 Debounce 機制

```
使用者按鍵 → 重置 debounce timer（800ms）
                    ↓（無新按鍵）
              800ms 後 timer 觸發
                    ↓
              檢查觸發條件（§2.1）
                    ↓ 全部符合
              送出 AI 分析請求（async）
                    ↓ 分析期間使用者又按鍵
              取消本次請求，重置 timer
```

debounce 時間可在設定頁面調整（範圍：300ms – 2000ms）。

### 2.3 不觸發的情況

- 組字區只有注音符號（尚未完成任何漢字組字）
- 目前組字區全為英文（`englishBuffer` 模式中）
- 使用者正在瀏覽候選窗（`.ofCandidates`、`.ofSimilarPhonetic` 等）
- AI 引擎尚未完成初始化（模型載入中）

---

## 3. AI 引擎架構

### 3.1 XPC Service

建立獨立 XPC Service：`com.thomas.vChewing.AICorrector`

```
vChewing 主進程（IMKInputController）
    │  NSXPCConnection（async）
    ▼
AICorrector XPC Service
    ├── EngineProtocol
    │     ├── LocalMLXEngine   ← 預設
    │     └── CloudAPIEngine   ← 使用者選擇
    │
    └── 回傳 CorrectionResult
```

XPC Service 的優點：
- 模型記憶體（~450MB–1.8GB）在獨立進程中管理
- 首次使用時才啟動（lazy loading）
- 崩潰自動重啟，不影響輸入法
- 可被 macOS 的記憶體壓力機制獨立回收

### 3.2 EngineProtocol

```swift
protocol AICorrectorEngine {
    /// 修正同音字錯誤
    func correctSpelling(
        text: String,
        completion: @escaping (CorrectionResult) -> Void
    )

    /// 語意重寫建議
    func suggestRewrite(
        text: String,
        completion: @escaping (RewriteResult) -> Void
    )
}

struct CorrectionResult {
    let original: String
    let corrected: String
    let corrections: [SingleCorrection]  // 每個修正點的詳細資訊
    let confidence: Float                // 0.0 – 1.0，低於閾值不套用
}

struct SingleCorrection {
    let range: Range<String.Index>   // 在 original 中的位置
    let original: String             // 原始字
    let corrected: String            // 修正後的字
    let reason: CorrectionReason
}

enum CorrectionReason {
    case homophones          // 同音字錯誤（攻克→功課）
    case similarPhonetic     // 近似音錯誤（ㄣ/ㄥ 混用等）
    case contextualMeaning   // 語意不通順
}

struct RewriteResult {
    let original: String
    let suggestion: String
    let isSignificantlyDifferent: Bool  // 差異過大時不自動套用，僅提示
}
```

### 3.3 本地引擎：LocalMLXEngine

**框架**：MLX Swift（`mlx-swift` package）  
**模型**：Qwen2.5-Instruct 量化版（使用者可選）

| 選項 | 模型 | 大小（4-bit量化） | 適用場景 |
|------|------|-----------------|---------|
| 輕量（預設） | Qwen2.5-1.5B-Instruct | ~450MB | 速度優先，M1/M2 |
| 精準 | Qwen2.5-3B-Instruct | ~900MB | 準確率優先，M2 Pro+ |

**模型來源**：`mlx-community` HuggingFace 倉庫，首次啟用時下載。

**推理延遲估計（Apple Silicon）**：

| 機型 | 1.5B 模型 | 3B 模型 |
|------|---------|--------|
| M1 | ~200ms | ~450ms |
| M2 | ~150ms | ~320ms |
| M4 | ~100ms | ~200ms |

### 3.4 雲端引擎：CloudAPIEngine

使用者在設定頁面填入 API key 後啟用。支援多個 provider：

| Provider | 模型 | 繁中品質 | 費用 |
|---------|------|---------|------|
| Google Gemini Flash 2.0（推薦） | gemini-2.0-flash | ★★★★★ | 極低 |
| Anthropic Claude Haiku 3.5 | claude-haiku-3-5 | ★★★★★ | 低 |
| OpenAI GPT-4o mini | gpt-4o-mini | ★★★★☆ | 低 |

**隱私提示**：雲端模式下，使用者的輸入文字會被送至第三方服務。設定頁面須有明確警示，且每次切換至雲端模式時彈出確認對話框（可選擇「不再提示」）。

---

## 4. Prompt 設計

### 4.1 CSC 任務 Prompt（繁體中文修正）

**System Prompt**：
```
你是一個繁體中文輸入法的拼字修正助手。
使用者剛剛透過注音輸入法輸入了一段文字，可能含有同音字錯誤或近似音錯誤。
請分析輸入文字的語意，修正其中用錯的同音字或近音字。

規則：
1. 只修正拼音/聲韻相同或相近的用字錯誤，不修改文意本身
2. 若整句文意合理，請原文回傳，不做任何修改
3. 回傳格式為 JSON：{"corrected": "修正後文字", "changes": [{"from": "原字", "to": "修正字", "position": 位置}]}
4. position 從 0 開始計數
5. 若無需修正，changes 為空陣列
6. 不要加任何說明或前綴，只回傳 JSON
```

**User Prompt**：
```
輸入文字：{preeditText}
```

**範例**：
- 輸入：`在家裡寫攻克` → `{"corrected": "在家裡寫功課", "changes": [{"from": "攻克", "to": "功課", "position": 4}]}`
- 輸入：`這個作業再血衣次` → `{"corrected": "這個作業再寫一次", "changes": [{"from": "血衣", "to": "寫一", "position": 6}]}`
- 輸入：`今天天氣很好` → `{"corrected": "今天天氣很好", "changes": []}`

### 4.2 Rewrite 任務 Prompt（語意重寫）

**System Prompt**：
```
你是一個繁體中文寫作助手。
使用者輸入了一段文字，請評估是否有更自然、更通順的說法。

規則：
1. 只在原文有明顯改善空間時才給建議，否則回傳 null
2. 建議的改寫應保持原意，不添加或刪除資訊
3. 回傳格式為 JSON：{"suggestion": "改寫後文字"} 或 {"suggestion": null}
4. 不要加任何說明，只回傳 JSON
```

**User Prompt**：
```
原文：{preeditText}
```

### 4.3 Confidence 過濾

CorrectionResult 的 `confidence` 由以下規則計算（本地模型）：
- 模型輸出的 logit 分數轉換（若 MLX API 提供）
- 或：修正字數 / 總字數 比例作為風險指標（修改比例 > 40% 時 confidence 降低）

**預設閾值**：`confidence >= 0.7` 才自動套用，否則靜默忽略。

---

## 5. 套用修正至組字區

### 5.1 Node Override 流程

AI 分析完成後，主進程收到 `CorrectionResult`，執行以下流程：

```swift
func applyCorrection(_ result: CorrectionResult) {
    guard result.corrected != result.original else { return }
    guard result.confidence >= UserDef.aiCorrectionConfidenceThreshold else { return }

    // 1. 取得目前 Megrez compositor 的 node 列表
    let nodes = compositor.walkedNodes  // 每個 node 有 .value（顯示文字）和 .spanLength

    // 2. 將 CorrectionResult.corrections 中的每個修正點對應到 node
    for correction in result.corrections {
        guard let nodeIndex = findNodeIndex(for: correction.range, in: nodes) else { continue }
        // 3. 用 overrideCandidate 鎖定修正後的字
        compositor.overrideCandidate(
            correction.corrected,
            at: nodeIndex
        )
    }

    // 4. 重新組句
    compositor.walk()

    // 5. 更新顯示
    _ = generateStateOfInputting(sansReading: false)
    handle(state: stateOfInputting, input: nil)
}
```

### 5.2 Node Mapping 演算法

組字區的 `walkedNodes` 按順序排列，每個 node 的 `spanLength` 表示佔幾個字。透過累積 offset 可以找到字元位置對應的 node：

```swift
func findNodeIndex(for range: Range<String.Index>, in nodes: [Node]) -> Int? {
    let targetOffset = preeditText.distance(from: preeditText.startIndex, to: range.lowerBound)
    var currentOffset = 0
    for (i, node) in nodes.enumerated() {
        let nodeEnd = currentOffset + node.spanLength
        if currentOffset <= targetOffset && targetOffset < nodeEnd {
            return i
        }
        currentOffset = nodeEnd
    }
    return nil
}
```

**注意**：若一個修正跨越多個 node（如「血衣」→「寫一」橫跨兩個 node），需要對每個 node 分別套用 override。

### 5.3 修正後視覺提示

套用修正後，在組字區的修正字上方顯示底線或特殊標記（若 IMKit 支援），讓使用者知道哪些字被 AI 修改過。此為 nice-to-have，實作時視 IMKit 的 `setMarkedText` 的 attribute 支援程度而定。

---

## 6. 設定頁面

### 6.1 新增設定項目（UserDef）

需同步更新 `PrefMgrProtocol` 和 `PrefMgr`：

```swift
// AI 修正總開關
var aiCorrectionEnabled: Bool  // 預設：false

// 子功能開關
var aiCSCEnabled: Bool          // 預設：true（總開關開啟後）
var aiRewriteEnabled: Bool      // 預設：false（需使用者主動開啟）

// 閾值設定
var aiCSCThreshold: Int         // 預設：5（字）
var aiRewriteThreshold: Int     // 預設：10（字）
var aiDebounceMs: Int           // 預設：800（毫秒）
var aiConfidenceThreshold: Float // 預設：0.7

// 模型設定
var aiEngineType: AIEngineType  // .localMLX | .cloudAPI
var aiLocalModelSize: AIModelSize // .small_1_5B | .large_3B
var aiCloudProvider: AICloudProvider // .gemini | .anthropic | .openai
var aiCloudAPIKey: String       // 加密儲存於 Keychain，不存 UserDefaults
```

### 6.2 設定 UI 佈局（Cocoa + SwiftUI 雙版本）

```
┌─────────────────────────────────────────┐
│ AI 輔助輸入修正                    [開關] │
├─────────────────────────────────────────┤
│ 引擎選擇                                │
│   ● 本地模型（隱私保護）                │
│       模型大小：[輕量 1.5B ▼]          │
│       [下載模型] [已下載 ✓ 450MB]      │
│   ○ 雲端 API（需要 API Key）           │
│       服務商：[Google Gemini ▼]         │
│       API Key：[••••••••••] [測試連線] │
│       ⚠️ 您的輸入文字將被送至第三方    │
├─────────────────────────────────────────┤
│ 拼字修正（CSC）               [開關]   │
│   最少字數觸發：[5] 字                 │
│                                         │
│ 語意重寫建議                  [開關]   │
│   最少字數觸發：[10] 字                │
├─────────────────────────────────────────┤
│ 進階設定                                │
│   反應延遲：[800] ms                   │
│   修正信心閾值：[0.7]                  │
└─────────────────────────────────────────┘
```

---

## 7. 模型下載機制

### 7.1 下載流程

1. 使用者在設定頁面點擊「下載模型」
2. 顯示進度視窗（非阻塞）
3. 從 HuggingFace `mlx-community` 下載量化模型檔案
4. 儲存路徑：`~/Library/Application Support/vChewing/AIModels/{modelName}/`
5. 下載完成後驗證 SHA256，更新 UI 為「已下載 ✓」
6. XPC Service 在下次呼叫時自動載入

### 7.2 下載目標

| 模型 | HuggingFace repo | 主要檔案 |
|------|-----------------|---------|
| Qwen2.5-1.5B | `mlx-community/Qwen2.5-1.5B-Instruct-4bit` | `model.safetensors`、`config.json`、`tokenizer.json` 等 |
| Qwen2.5-3B | `mlx-community/Qwen2.5-3B-Instruct-4bit` | 同上 |

---

## 8. 新增檔案清單

| 檔案路徑 | 說明 |
|---------|------|
| `Sources/vChewing_MainAssembly4Darwin/AICorrector/AICorrectorXPC.swift` | XPC Service 定義與協定 |
| `Sources/vChewing_MainAssembly4Darwin/AICorrector/LocalMLXEngine.swift` | 本地 MLX 推理引擎 |
| `Sources/vChewing_MainAssembly4Darwin/AICorrector/CloudAPIEngine.swift` | 雲端 API 引擎（多 provider） |
| `Sources/vChewing_MainAssembly4Darwin/AICorrector/CorrectionApplier.swift` | Node Override 套用邏輯 |
| `Sources/vChewing_MainAssembly4Darwin/AICorrector/PromptBuilder.swift` | Prompt 組裝（CSC / Rewrite） |
| `Sources/vChewing_Typewriter/InputHandler_HandleAICorrection.swift` | debounce timer、觸發邏輯 |
| `Sources/vChewing_Shared/UserDef+AI.swift` | AI 相關 UserDef keys 擴充 |
| `com.thomas.vChewing.AICorrector/` | XPC Service target 目錄 |

所有新檔案加 `#if canImport(Darwin)` 閘控。

---

## 9. 實作注意事項（給 AI Agent）

### 9.1 XPC Service 設定

- XPC Service 需在 Xcode project 中新增為獨立 target
- Bundle identifier：`com.thomas.vChewing.AICorrector`
- 需在主 app 的 `Info.plist` 中宣告 `NSXPCServices` 鍵
- XPC 協定需用 `@objc` 標記，參數類型必須符合 `NSSecureCoding`

### 9.2 MLX Swift 整合

- 加入 Swift Package：`https://github.com/ml-explore/mlx-swift`
- 依賴項：`MLX`、`MLXNN`、`MLXRandom`、`Transformers`（mlx-swift-examples 的 tokenizer 部分）
- MLX 只支援 Apple Silicon，Intel Mac 會編譯失敗；需在 Package.swift 中加條件編譯
- 模型推理需在 XPC Service 的 background thread 執行，避免 block XPC main queue

### 9.3 Keychain 儲存 API Key

- 雲端 API Key **不可**存入 `UserDefaults`
- 使用 `Security.framework` 的 `SecItemAdd` / `SecItemCopyMatching` 存取 Keychain
- Service name：`com.thomas.vChewing.cloudAPIKey`

### 9.4 CorrectionApplier 的邊界條件

- 若 AI 回傳的修正字數與原字數不同（如「血衣」2字→「寫一」2字 OK，但「一下」2字→「一會兒」3字 NG），**跳過該修正**（不同長度的替換在 Node Override 架構下不安全）
- 若組字區在 AI 分析期間已被使用者修改（對比 requestText 與目前 preeditText），**丟棄結果**

### 9.5 debounce timer

- 在 `InputHandler` 中宣告 `private var aiDebounceTimer: Timer?`
- 每次按鍵後：`aiDebounceTimer?.invalidate(); aiDebounceTimer = Timer.scheduledTimer(...)`
- 注意 Timer 需在 main run loop 上執行

---

## 10. 測試案例

### 10.1 CSC 修正正確性

| 輸入文字 | 期望修正結果 | 說明 |
|---------|------------|------|
| `在家裡寫攻克` | `在家裡寫功課` | 典型同音字錯誤 |
| `這個作業再血衣次` | `這個作業再寫一次` | 近似音錯誤 |
| `今天天氣很好` | `今天天氣很好`（不修改） | 正確輸入不應被修改 |
| `他去市場賣東西` | `他去市場賣東西`（不修改） | 正確輸入不應被修改 |
| `我在這裡等後` | `我在這裡等候` | 語意相近但用字錯誤 |

### 10.2 觸發條件測試

| 情境 | 期望行為 |
|------|---------|
| 組字區 4 字，暫停 800ms | 不觸發（未達閾值） |
| 組字區 6 字，暫停 800ms | 觸發 CSC |
| 組字區 6 字，持續輸入中 | 不觸發（debounce 持續重置） |
| 候選窗開啟中，暫停 800ms | 不觸發（狀態不符） |
| 組字區 6 字，AI 分析中，使用者繼續輸入 | 取消分析，重置 timer |

### 10.3 Node Mapping 測試

- 單字節點修正：「攻」→「功」（1 字 node）
- 雙字節點修正：「攻克」→「功課」（2 字 node）
- 跨節點修正：「血衣」（各為獨立 node）→「寫一」

### 10.4 設定頁面測試

- 總開關關閉：CSC 和 Rewrite 開關灰化
- 本地模型未下載：推理時顯示「模型尚未下載」提示
- 雲端 API Key 錯誤：`testConnection()` 回傳錯誤，UI 顯示紅色警示
- 切換至雲端模式：顯示隱私警示對話框

---

## 11. 未來擴充（暫緩）

- **Undo 整合**：在 client app 層透過 `insertText` 替換並支援 Cmd+Z，需針對各 app（Safari、Notes、VS Code 等）測試相容性
- **個人化學習**：記錄使用者拒絕的修正建議，避免重複出現相同錯誤修正
- **更長 context**：目前只分析組字區內的文字，未來可納入前一句（已送出文字）作為語境
- **語音相近度評分**：整合 Tekkon 的聲韻距離計算，提升 confidence 準確度

---

*規格書版本：v0.1 / 2026-04-17*  
*下一步：PoC 驗證 Qwen2.5-1.5B 對繁中 CSC 的實際準確率*
