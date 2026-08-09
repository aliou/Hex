import AVFoundation
import AppKit
import ComposableArchitecture
import CoreAudio
import Dependencies
import HexCore
import IdentifiedCollections
import Sauce
import ServiceManagement
import SwiftUI

private let settingsLogger = HexLog.settings
private typealias SettingsAudioPropertyListenerBlock = @convention(block) (UInt32, UnsafePointer<AudioObjectPropertyAddress>) -> Void

private enum HotKeyCaptureTarget: Equatable {
  /// Capturing a new recording hotkey to append.
  case newRecording
  /// Re-capturing the recording hotkey at the given index in `hexSettings.hotkeys`.
  case recording(Int)
  case pasteLastTranscript
}

extension SharedReaderKey
  where Self == InMemoryKey<Bool>.Default
{
  static var isSettingHotKey: Self {
    Self[.inMemory("isSettingHotKey"), default: false]
  }
  
  static var isSettingPasteLastTranscriptHotkey: Self {
    Self[.inMemory("isSettingPasteLastTranscriptHotkey"), default: false]
  }

  static var isRemappingScratchpadFocused: Self {
    Self[.inMemory("isRemappingScratchpadFocused"), default: false]
  }
}

// MARK: - Settings Feature

@Reducer
struct SettingsFeature {
  @ObservableState
  struct State {
    @Shared(.hexSettings) var hexSettings: HexSettings
    @Shared(.isSettingHotKey) var isSettingHotKey: Bool = false
    @Shared(.isSettingPasteLastTranscriptHotkey) var isSettingPasteLastTranscriptHotkey: Bool = false
    @Shared(.isRemappingScratchpadFocused) var isRemappingScratchpadFocused: Bool = false
    @Shared(.transcriptionHistory) var transcriptionHistory: TranscriptionHistory
    @Shared(.hotkeyPermissionState) var hotkeyPermissionState: HotkeyPermissionState

    /// Slot of the recording hotkey being re-captured (index into `hexSettings.hotkeys`).
    /// Ignored while capturing a brand-new hotkey.
    var settingHotKeyIndex: Int = 0
    /// True while "Add Hot Key" capture is pending (no placeholder stored yet).
    var isAddingHotKey: Bool = false

    var languages: IdentifiedArrayOf<Language> = []
    var currentModifiers: Modifiers = .init(modifiers: [])
    var currentPasteLastModifiers: Modifiers = .init(modifiers: [])
    var remappingScratchpadText: String = ""
    
    // Available microphones
    var availableInputDevices: [AudioInputDevice] = []
    var defaultInputDeviceName: String?

    // Model Management
    var modelDownload = ModelDownloadFeature.State()
    var cleanupModel = CleanupModelFeature.State()
    var shouldFlashModelSection = false

  }

  enum Action: BindableAction {
    case binding(BindingAction<State>)

    // Existing
    case task
    case startSettingHotKey(index: Int)
    case addHotKey
    case cancelSettingHotKey
    case removeHotKey(Int)
    case startSettingPasteLastTranscriptHotkey
    case clearPasteLastTranscriptHotkey
    case keyEvent(KeyEvent)
    case toggleOpenOnLogin(Bool)
    case toggleShowDockIcon(Bool)
    case togglePreventSystemSleep(Bool)
    case setRecordingAudioBehavior(RecordingAudioBehavior)
    case toggleSuperFastMode(Bool)
    case setUseClipboardPaste(Bool)
    case setCopyToClipboard(Bool)
    case setDoubleTapLockEnabled(Bool)
    case setUseDoubleTapOnly(Bool)
    case setMinimumKeyTime(Double)
    case setOutputLanguage(String?)
    case setSelectedMicrophoneID(String?)
    case setSoundEffectsEnabled(Bool)
    case setSoundEffectsVolume(Double)

    // Permission delegation (forwarded to AppFeature)
    case requestMicrophone
    case requestAccessibility
    case requestInputMonitoring

    // Microphone selection
    case loadAvailableInputDevices
    case availableInputDevicesLoaded([AudioInputDevice], String?)

    // Model Management
    case modelDownload(ModelDownloadFeature.Action)
    case cleanupModel(CleanupModelFeature.Action)
    
    // History Management
    case toggleSaveTranscriptionHistory(Bool)
    case setMaxHistoryEntries(Int?)

    // Modifier configuration
    case setModifierSide(index: Int, kind: Modifier.Kind, side: Modifier.Side)

    // Word remappings
    case setWordRemovalsEnabled(Bool)
    case addWordRemoval
    case updateWordRemoval(WordRemoval)
    case removeWordRemoval(UUID)
    case addWordRemapping
    case updateWordRemapping(WordRemapping)
    case removeWordRemapping(UUID)
    case setRemappingScratchpadFocused(Bool)
    case setLowercaseTranscripts(Bool)
    case setRemovePunctuation(Bool)
    case setTranscriptCleanupEnabled(Bool)
    case setTranscriptCleanupAppContextEnabled(Bool)
  }

  @Dependency(\.keyEventMonitor) var keyEventMonitor
  @Dependency(\.transcription) var transcription
  @Dependency(\.recording) var recording
  @Dependency(\.soundEffects) var soundEffects
  @Dependency(\.transcriptPersistence) var transcriptPersistence

  private func deleteAudioEffect(for transcripts: [Transcript]) -> Effect<Action> {
    .run { [transcriptPersistence] _ in
      for transcript in transcripts {
        try? await transcriptPersistence.deleteAudio(transcript)
      }
    }
  }

  private func beginCapture(_ target: HotKeyCaptureTarget, state: inout State) {
    switch target {
    case .newRecording:
      state.$isSettingHotKey.withLock { $0 = true }
      state.currentModifiers = .init(modifiers: [])
      state.isAddingHotKey = true
    case .recording:
      state.$isSettingHotKey.withLock { $0 = true }
      state.currentModifiers = .init(modifiers: [])
    case .pasteLastTranscript:
      state.$isSettingPasteLastTranscriptHotkey.withLock { $0 = true }
      state.currentPasteLastModifiers = .init(modifiers: [])
    }
  }

  private func endCapture(_ target: HotKeyCaptureTarget, state: inout State) {
    switch target {
    case .newRecording, .recording:
      state.$isSettingHotKey.withLock { $0 = false }
      state.currentModifiers = .init(modifiers: [])
      state.isAddingHotKey = false
    case .pasteLastTranscript:
      state.$isSettingPasteLastTranscriptHotkey.withLock { $0 = false }
      state.currentPasteLastModifiers = .init(modifiers: [])
    }
  }

  private func captureModifiers(for target: HotKeyCaptureTarget, state: State) -> Modifiers {
    switch target {
    case .newRecording, .recording:
      state.currentModifiers
    case .pasteLastTranscript:
      state.currentPasteLastModifiers
    }
  }

  private func updateCaptureModifiers(_ modifiers: Modifiers, for target: HotKeyCaptureTarget, state: inout State) {
    switch target {
    case .newRecording, .recording:
      state.currentModifiers = modifiers
    case .pasteLastTranscript:
      state.currentPasteLastModifiers = modifiers
    }
  }

  private func applyCapturedHotKey(key: Key?, modifiers: Modifiers, for target: HotKeyCaptureTarget, state: inout State) {
    let captured = HotKey(key: key, modifiers: modifiers.erasingSides())
    switch target {
    case .newRecording:
      state.$hexSettings.withLock {
        // Don't keep duplicate chords
        guard !$0.hotkeys.contains(captured) else { return }
        $0.hotkeys.append(captured)
      }
    case let .recording(index):
      state.$hexSettings.withLock {
        // Don't keep duplicate chords
        guard !$0.hotkeys.contains(captured) else { return }
        guard $0.hotkeys.indices.contains(index) else { return }
        $0.hotkeys[index] = captured
      }
    case .pasteLastTranscript:
      guard let key else { return }
      state.$hexSettings.withLock {
        $0.pasteLastTranscriptHotkey = captured
      }
    }
  }

  private func handleCapture(_ keyEvent: KeyEvent, for target: HotKeyCaptureTarget, state: inout State) -> Effect<Action> {
    if keyEvent.key == .escape {
      endCapture(target, state: &state)
      return .none
    }

    if let key = keyEvent.key {
      // A key press finalizes the chord. Use only the modifiers held when the
      // key went down (not accumulated ones), and strip fn: macOS sets the
      // function flag on F-key events ("fn + top row" is how F-keys are
      // produced), so keeping it would store Fn+FX instead of FX.
      var chordModifiers = keyEvent.modifiers.removing(kind: .fn)
      if target == .pasteLastTranscript, chordModifiers.isEmpty {
        return .none
      }
      // Preserve left/right side information for modifier-only hotkeys by
      // re-accumulating modifier-only events; for key chords sides don't
      // matter (erased in applyCapturedHotKey).
      applyCapturedHotKey(key: key, modifiers: chordModifiers, for: target, state: &state)
      endCapture(target, state: &state)
      return .none
    }

    // Modifier-only events accumulate, so multi-modifier chords can be built up.
    let updatedModifiers = keyEvent.modifiers.union(captureModifiers(for: target, state: state))
    updateCaptureModifiers(updatedModifiers, for: target, state: &state)

    if case .newRecording = target, keyEvent.modifiers.isEmpty {
      applyCapturedHotKey(key: nil, modifiers: updatedModifiers, for: target, state: &state)
      endCapture(target, state: &state)
    }

    if case .recording = target, keyEvent.modifiers.isEmpty {
      applyCapturedHotKey(key: nil, modifiers: updatedModifiers, for: target, state: &state)
      endCapture(target, state: &state)
    }

    return .none
  }


  var body: some ReducerOf<Self> {
    BindingReducer()

    Scope(state: \.modelDownload, action: \.modelDownload) {
      ModelDownloadFeature()
    }

    Scope(state: \.cleanupModel, action: \.cleanupModel) {
      CleanupModelFeature()
    }

    Reduce { state, action in
      switch action {
      case .binding:
        let didNormalizeDoubleTapOnly = !state.hexSettings.doubleTapLockEnabled && state.hexSettings.useDoubleTapOnly
        if didNormalizeDoubleTapOnly {
          state.$hexSettings.withLock {
            $0.useDoubleTapOnly = false
          }
        }

        return .none

      case .task:
        if let url = Bundle.main.url(forResource: "languages", withExtension: "json"),
          let data = try? Data(contentsOf: url),
          let languages = try? JSONDecoder().decode([Language].self, from: data)
        {
          state.languages = IdentifiedArray(uniqueElements: languages)
        } else {
          settingsLogger.error("Failed to load languages JSON from bundle")
        }

        // Listen for key events and load microphones (existing + new)
        return .run { send in
          func audioPropertyAddress(
            _ selector: AudioObjectPropertySelector,
            scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
            element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain
          ) -> AudioObjectPropertyAddress {
            AudioObjectPropertyAddress(
              mSelector: selector,
              mScope: scope,
              mElement: element
            )
          }

          await send(.modelDownload(.fetchModels))
          await send(.loadAvailableInputDevices)

          // Listen for device connection/disconnection notifications
          // Using a simpler debounced approach with a single task
          var deviceUpdateTask: Task<Void, Never>?
          var audioHardwareObservers: [(AudioObjectPropertySelector, SettingsAudioPropertyListenerBlock)] = []

          // Helper function to debounce device updates
          func debounceDeviceUpdate() {
            deviceUpdateTask?.cancel()
            deviceUpdateTask = Task {
              try? await Task.sleep(nanoseconds: 500_000_000) // 500ms
              if !Task.isCancelled {
                await send(.loadAvailableInputDevices)
              }
            }
          }

          func installAudioHardwareObserver(_ selector: AudioObjectPropertySelector) {
            let listener: SettingsAudioPropertyListenerBlock = { _, _ in
              debounceDeviceUpdate()
            }
            var address = audioPropertyAddress(selector)
            let status = AudioObjectAddPropertyListenerBlock(
              AudioObjectID(kAudioObjectSystemObject),
              &address,
              DispatchQueue.main,
              listener
            )

            if status == noErr {
              audioHardwareObservers.append((selector, listener))
            } else {
              settingsLogger.error("Failed to observe audio hardware selector \(selector): \(status)")
            }
          }

          let deviceConnectionObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name(rawValue: "AVCaptureDeviceWasConnected"),
            object: nil,
            queue: .main
          ) { _ in
            debounceDeviceUpdate()
          }
          
          let deviceDisconnectionObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name(rawValue: "AVCaptureDeviceWasDisconnected"),
            object: nil,
            queue: .main
          ) { _ in
            debounceDeviceUpdate()
          }

          let appDidBecomeActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
          ) { _ in
            debounceDeviceUpdate()
          }

          let wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
          ) { _ in
            debounceDeviceUpdate()
          }

          installAudioHardwareObserver(kAudioHardwarePropertyDefaultInputDevice)
          installAudioHardwareObserver(kAudioHardwarePropertyDevices)

          // Be sure to clean up resources when the task is finished
          defer {
            deviceUpdateTask?.cancel()
            NotificationCenter.default.removeObserver(deviceConnectionObserver)
            NotificationCenter.default.removeObserver(deviceDisconnectionObserver)
            NotificationCenter.default.removeObserver(appDidBecomeActiveObserver)
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)

            for (selector, listener) in audioHardwareObservers {
              var address = audioPropertyAddress(selector)
              let status = AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                DispatchQueue.main,
                listener
              )
              if status != noErr {
                settingsLogger.error("Failed to remove audio hardware observer for selector \(selector): \(status)")
              }
            }
          }

          for try await keyEvent in await keyEventMonitor.listenForKeyPress() {
            await send(.keyEvent(keyEvent))
          }
          
        }

      case let .startSettingHotKey(index):
        state.settingHotKeyIndex = index
        beginCapture(.recording(index), state: &state)
        return .none

      case .addHotKey:
        beginCapture(.newRecording, state: &state)
        return .none

      case .cancelSettingHotKey:
        guard state.isSettingHotKey else { return .none }
        endCapture(.newRecording, state: &state)
        return .none

      case let .removeHotKey(index):
        state.$hexSettings.withLock {
          guard $0.hotkeys.count > 1, $0.hotkeys.indices.contains(index) else { return }
          $0.hotkeys.remove(at: index)
        }
        return .none

      case .addWordRemoval:
        state.$hexSettings.withLock {
          $0.wordRemovals.append(.init(pattern: ""))
        }
        return .none

      case let .updateWordRemoval(removal):
        state.$hexSettings.withLock {
          guard let index = $0.wordRemovals.firstIndex(where: { $0.id == removal.id }) else { return }
          $0.wordRemovals[index] = removal
        }
        return .none

      case let .removeWordRemoval(id):
        state.$hexSettings.withLock {
          $0.wordRemovals.removeAll { $0.id == id }
        }
        return .none

      case .addWordRemapping:
        state.$hexSettings.withLock {
          $0.wordRemappings.append(.init(match: "", replacement: ""))
        }
        return .none

      case let .updateWordRemapping(remapping):
        state.$hexSettings.withLock {
          guard let index = $0.wordRemappings.firstIndex(where: { $0.id == remapping.id }) else { return }
          $0.wordRemappings[index] = remapping
        }
        return .none

      case let .removeWordRemapping(id):
        state.$hexSettings.withLock {
          $0.wordRemappings.removeAll { $0.id == id }
        }
        return .none

      case let .setRemappingScratchpadFocused(isFocused):
        state.$isRemappingScratchpadFocused.withLock { $0 = isFocused }
        return .none

      case let .setLowercaseTranscripts(enabled):
        state.$hexSettings.withLock { $0.lowercaseTranscripts = enabled }
        return .none

      case let .setRemovePunctuation(enabled):
        state.$hexSettings.withLock { $0.removePunctuation = enabled }
        return .none

      case let .setTranscriptCleanupEnabled(enabled):
        state.$hexSettings.withLock { $0.transcriptCleanupEnabled = enabled }
        return .none

      case let .setTranscriptCleanupAppContextEnabled(enabled):
        state.$hexSettings.withLock { $0.transcriptCleanupAppContextEnabled = enabled }
        return .none

      case .startSettingPasteLastTranscriptHotkey:
        beginCapture(.pasteLastTranscript, state: &state)
        return .none
        
      case .clearPasteLastTranscriptHotkey:
        state.$hexSettings.withLock { $0.pasteLastTranscriptHotkey = nil }
        return .none

      case let .keyEvent(keyEvent):
        if state.isSettingPasteLastTranscriptHotkey {
          return handleCapture(keyEvent, for: .pasteLastTranscript, state: &state)
        }

        guard state.isSettingHotKey else { return .none }
        let target: HotKeyCaptureTarget = state.isAddingHotKey
          ? .newRecording
          : .recording(state.settingHotKeyIndex)
        return handleCapture(keyEvent, for: target, state: &state)

      case let .toggleOpenOnLogin(enabled):
        state.$hexSettings.withLock { $0.openOnLogin = enabled }
        return .run { _ in
          if enabled {
            try? SMAppService.mainApp.register()
          } else {
            try? SMAppService.mainApp.unregister()
          }
        }

      case let .toggleShowDockIcon(enabled):
        state.$hexSettings.withLock { $0.showDockIcon = enabled }
        return .run { _ in
          await MainActor.run {
            NotificationCenter.default.post(name: .updateAppMode, object: nil)
          }
        }

      case let .togglePreventSystemSleep(enabled):
        state.$hexSettings.withLock { $0.preventSystemSleep = enabled }
        return .none

      case let .setUseClipboardPaste(enabled):
        state.$hexSettings.withLock { $0.useClipboardPaste = enabled }
        return .none

      case let .setCopyToClipboard(enabled):
        state.$hexSettings.withLock { $0.copyToClipboard = enabled }
        return .none

      case let .setRecordingAudioBehavior(behavior):
        state.$hexSettings.withLock { $0.recordingAudioBehavior = behavior }
        return .none

      case let .toggleSuperFastMode(enabled):
        state.$hexSettings.withLock { $0.superFastModeEnabled = enabled }
        return .run { _ in
          await recording.warmUpRecorder()
        }

      case let .setDoubleTapLockEnabled(enabled):
        state.$hexSettings.withLock {
          $0.doubleTapLockEnabled = enabled
          if !enabled {
            $0.useDoubleTapOnly = false
          }
        }
        return .none

      case let .setUseDoubleTapOnly(enabled):
        state.$hexSettings.withLock {
          $0.useDoubleTapOnly = enabled && $0.doubleTapLockEnabled
        }
        return .none

      case let .setMinimumKeyTime(value):
        state.$hexSettings.withLock { $0.minimumKeyTime = value }
        return .none

      case let .setOutputLanguage(language):
        state.$hexSettings.withLock { $0.outputLanguage = language }
        return .none

      case let .setSelectedMicrophoneID(deviceID):
        state.$hexSettings.withLock { $0.selectedMicrophoneID = deviceID }
        return .run { _ in
          await recording.warmUpRecorder()
        }

      case let .setSoundEffectsEnabled(enabled):
        state.$hexSettings.withLock { $0.soundEffectsEnabled = enabled }
        return .run { _ in
          await soundEffects.setEnabled(enabled)
        }

      case let .setSoundEffectsVolume(volume):
        state.$hexSettings.withLock { $0.soundEffectsVolume = volume }
        return .none

      // Permission requests
      case .requestMicrophone:
        settingsLogger.info("User requested microphone permission from settings")
        return .none

      case .requestAccessibility:
        settingsLogger.info("User requested accessibility permission from settings")
        return .none

      case .requestInputMonitoring:
        settingsLogger.info("User requested input monitoring permission from settings")
        return .none

      // Model Management
      case .modelDownload:
        return .none

      case .cleanupModel:
        return .none
      
      // Microphone device selection
      case .loadAvailableInputDevices:
        return .run { send in
          let devices = await recording.getAvailableInputDevices()
          let defaultName = await recording.getDefaultInputDeviceName()
          await send(.availableInputDevicesLoaded(devices, defaultName))
        }
        
      case let .availableInputDevicesLoaded(devices, defaultName):
        if let selectedMicrophoneID = state.hexSettings.selectedMicrophoneID,
           let device = devices.first(where: { $0.legacyID == selectedMicrophoneID }) {
          state.availableInputDevices = devices
          state.defaultInputDeviceName = defaultName
          return .send(.setSelectedMicrophoneID(device.id))
        }
        state.availableInputDevices = devices
        state.defaultInputDeviceName = defaultName
        return .none
        
      case let .toggleSaveTranscriptionHistory(enabled):
        state.$hexSettings.withLock { $0.saveTranscriptionHistory = enabled }
        
        // If disabling history, delete all existing entries
        if !enabled {
          let transcripts = state.transcriptionHistory.history
          
          // Clear the history
          state.$transcriptionHistory.withLock { history in
            history.history.removeAll()
          }

          return deleteAudioEffect(for: transcripts)
        }
        
        return .none

      case let .setMaxHistoryEntries(maxHistoryEntries):
        state.$hexSettings.withLock { $0.maxHistoryEntries = maxHistoryEntries }
        return .none

      case let .setModifierSide(index, kind, side):
        state.$hexSettings.withLock {
          guard $0.hotkeys.indices.contains(index),
                $0.hotkeys[index].key == nil else { return }
          $0.hotkeys[index].modifiers = $0.hotkeys[index].modifiers.setting(kind: kind, to: side)
        }
        return .none

      case let .setWordRemovalsEnabled(enabled):
        state.$hexSettings.withLock { $0.wordRemovalsEnabled = enabled }
        return .none

      }
    }
  }
}
