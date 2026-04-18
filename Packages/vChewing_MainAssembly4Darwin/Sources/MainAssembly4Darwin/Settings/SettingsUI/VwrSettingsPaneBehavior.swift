// (c) 2021 and onwards The vChewing Project (MIT-NTL License).
// ====================
// This code is released under the MIT license (SPDX-License-Identifier: MIT)
// ... with NTL restriction stating that:
// No trademark license is granted to use the trade names, trademarks, service
// marks, or product names of Contributor, except as required to fulfill notice
// requirements defined in MIT License.

import SwiftUI

// MARK: - VwrSettingsPaneBehavior

@available(macOS 14, *)
public struct VwrSettingsPaneBehavior: View {
  @AppStorage(UserDef.kAICorrectionEnabled.rawValue)
  private var aiCorrectionEnabled: Bool = UserDef.kAICorrectionEnabled.boolDefaultValue
  @AppStorage(UserDef.kAICloudProvider.rawValue)
  private var aiCloudProvider: String = UserDef.kAICloudProvider.stringDefaultValue
  @AppStorage(UserDef.kAICloudAPIKey.rawValue)
  private var aiCloudAPIKey: String = ""

  // MARK: - Main View

  public var body: some View {
    Form {
      Section {
        UserDef.kSpecifiedNotifyUIColorScheme.renderUI()
        UserDef.kShowNotificationsWhenTogglingCapsLock.renderUI()
        UserDef.kShowNotificationsWhenTogglingEisu.renderUI()
        UserDef.kShowNotificationsWhenTogglingShift.renderUI()
        UserDef.kAlwaysShowTooltipTextsHorizontally.renderUI()
          .disabled(Bundle.main.preferredLocalizations[0] == "en")
        UserDef.kBeepSoundPreference.renderUI()
      }

      Section {
        UserDef.kChooseCandidateUsingSpace.renderUI()
        UserDef.kEscToCleanInputBuffer.renderUI()
        UserDef.kAlsoConfirmAssociatedCandidatesByEnter.renderUI()
        UserDef.kSpecifyShiftBackSpaceKeyBehavior.renderUI()
        UserDef.kSpecifyShiftTabKeyBehavior.renderUI()
          .pickerStyle(RadioGroupPickerStyle())
      }

      Section {
        UserDef.kSpecifyShiftSpaceKeyBehavior.renderUI()
        UserDef.kUseSpaceToCommitHighlightedSCPCCandidate.renderUI()
      }

      Section {
        UserDef.kSpecifyCmdOptCtrlEnterBehavior.renderUI()
        VStack(alignment: .leading) {
          UserDef.kReflectBPMFVSInCompositionBuffer.renderUI()
          if let urlBPMFVS = URL(string: "https://github.com/ButTaiwan/bpmfvs") {
            Link(destination: urlBPMFVS) {
              Text(verbatim: "→ BPMFVS @ GitHub")
                .controlSize(.small)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .foregroundStyle(Color.accentColor)
            }
          }
        }
      }

      Section {
        UserDef.kUpperCaseLetterKeyBehavior.renderUI()
        UserDef.kNumPadCharInputBehavior.renderUI()
        UserDef.kSymbolTableEnabled.renderUI()
      }

      Section {
        UserDef.kSpecifyIntonationKeyBehavior.renderUI()
        UserDef.kAcceptLeadingIntonations.renderUI()
        UserDef.kSmartChineseEnglishSwitchEnabled.renderUI()
        UserDef.kAutoBracketPairingEnabled.renderUI()
        UserDef.kNumberQuickInputEnabled.renderUI()
      }

      Section {
        UserDef.kBypassNonAppleCapsLockHandling.renderUI()
        UserDef.kShareAlphanumericalModeStatusAcrossClients.renderUI()
        VStack(alignment: .leading) {
          UserDef.kTogglingAlphanumericalModeWithLShift.renderUI {
            SessionUI.shared.resyncShiftKeyUpCheckerSettings()
          }
          UserDef.kTogglingAlphanumericalModeWithRShift.renderUI {
            SessionUI.shared.resyncShiftKeyUpCheckerSettings()
          }
          Spacer()
          Group {
            Text(" ") +
              Text(LocalizedStringKey("This feature requires macOS \("10.15") and above."))
              + Text(CtlSettingsUI.sentenceSeparator)
              + Text("i18n:settings.shiftKeyASCIITogle.description".i18n)
          }.settingsDescription()
        }
        UserDef.kShiftEisuToggleOffTogetherWithCapsLock.renderUI()
      }

      Section {
        UserDef.kAICorrectionEnabled.renderUI()
        if aiCorrectionEnabled {
          UserDef.kAICSCEnabled.renderUI()
          UserDef.kAIRewriteEnabled.renderUI()
          Picker("引擎", selection: $aiCloudProvider) {
            Text("Ollama（本機，免 API Key）").tag("ollama")
            Text("Anthropic Claude").tag("anthropic")
            Text("Google Gemini").tag("gemini")
            Text("OpenAI").tag("openai")
          }
          .pickerStyle(.menu)
          if aiCloudProvider == "ollama" {
            Text("需先在終端機執行：ollama serve，並下載模型 qwen2.5:3b")
              .font(.caption)
              .foregroundStyle(.secondary)
          } else {
            HStack {
              Text("API Key")
                .frame(width: 80, alignment: .trailing)
              SecureField("貼上您的 API Key", text: $aiCloudAPIKey)
                .textFieldStyle(.roundedBorder)
            }
            Text("API Key 暫存於 UserDefaults（PoC 用途）。")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
      }
    }.formStyled()
      .frame(
        minWidth: CtlSettingsUI.formWidth,
        maxHeight: CtlSettingsUI.contentMaxHeight
      )
  }
}

// MARK: - VwrSettingsPaneBehavior_Previews

@available(macOS 14, *)
struct VwrSettingsPaneBehavior_Previews: PreviewProvider {
  static var previews: some View {
    VwrSettingsPaneBehavior()
  }
}
