import AppKit
import ComposableArchitecture
import Dependencies
import HexCore
import IdentifiedCollections

struct CleanupModelAvailability: Equatable, Sendable {
  var modelID: String
  var isDownloaded: Bool
}

@Reducer
struct CleanupModelFeature {
  @ObservableState
  struct State: Equatable {
    @Shared(.hexSettings) var hexSettings: HexSettings

    var models = IdentifiedArrayOf(uniqueElements: CleanupModels.curated)
    var isDownloading = false
    var downloadProgress: Double = 0
    var downloadError: String?
    var downloadingModelID: String?

    var selectedModelID: String { hexSettings.selectedTranscriptCleanupModel }

    var selectedModel: CleanupModelInfo? {
      models[id: selectedModelID]
    }

    var selectedModelIsDownloaded: Bool {
      models[id: selectedModelID]?.isDownloaded == true
    }
  }

  enum Action: Equatable {
    case task
    case selectModel(String)
    case downloadModel(String)
    case downloadProgress(Double)
    case downloadCompleted(String)
    case downloadFailed(String)
    case deleteModel(String)
    case modelDeleted(String)
    case modelDeletionFailed(String)
    case openModelLocation(String)
    case availabilityLoaded([CleanupModelAvailability])
  }

  @Dependency(\.transcriptCleanup) var transcriptCleanup

  var body: some ReducerOf<Self> {
    Reduce { state, action in
      switch action {
      case .task:
        let modelIDs = state.models.map(\.internalName)
        return .run { send in
          var availability: [CleanupModelAvailability] = []
          for modelID in modelIDs {
            availability.append(.init(modelID: modelID, isDownloaded: await transcriptCleanup.isModelDownloaded(modelID)))
          }
          await send(.availabilityLoaded(availability))
        }

      case let .availabilityLoaded(availability):
        for item in availability {
          state.models[id: item.modelID]?.isDownloaded = item.isDownloaded
        }
        return .none

      case let .selectModel(modelID):
        state.$hexSettings.withLock { $0.selectedTranscriptCleanupModel = modelID }
        return .none

      case let .downloadModel(modelID):
        state.isDownloading = true
        state.downloadProgress = 0
        state.downloadError = nil
        state.downloadingModelID = modelID
        return .run { send in
          do {
            try await transcriptCleanup.downloadModel(modelID) { progress in
              Task { await send(.downloadProgress(progress.fractionCompleted)) }
            }
            await send(.downloadCompleted(modelID))
          } catch {
            await send(.downloadFailed(error.localizedDescription))
          }
        }

      case let .downloadProgress(progress):
        state.downloadProgress = progress
        return .none

      case let .downloadCompleted(modelID):
        state.isDownloading = false
        state.downloadProgress = 1
        state.downloadError = nil
        state.downloadingModelID = nil
        state.models[id: modelID]?.isDownloaded = true
        state.$hexSettings.withLock { $0.selectedTranscriptCleanupModel = modelID }
        return .none

      case let .downloadFailed(message):
        state.isDownloading = false
        state.downloadingModelID = nil
        state.downloadError = message
        return .none

      case let .deleteModel(modelID):
        return .run { send in
          do {
            try await transcriptCleanup.deleteModel(modelID)
            await send(.modelDeleted(modelID))
          } catch {
            await send(.modelDeletionFailed(error.localizedDescription))
          }
        }

      case let .modelDeleted(modelID):
        state.models[id: modelID]?.isDownloaded = false
        return .none

      case let .modelDeletionFailed(message):
        state.downloadError = message
        return .none

      case let .openModelLocation(modelID):
        return .run { _ in
          guard let url = await transcriptCleanup.modelLocation(modelID) else { return }
          await MainActor.run {
            NSWorkspace.shared.activateFileViewerSelecting([url])
          }
        }
      }
    }
  }
}
