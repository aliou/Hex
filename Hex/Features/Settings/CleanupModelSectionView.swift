import AppKit
import ComposableArchitecture
import Inject
import SwiftUI

struct CleanupModelSectionView: View {
  @ObserveInjection var inject
  @Bindable var store: StoreOf<SettingsFeature>

  var body: some View {
    Section("Transcript Cleanup") {
      Toggle(
        "Clean up transcripts with local model",
        isOn: Binding(
          get: { store.hexSettings.transcriptCleanupEnabled },
          set: { store.send(.setTranscriptCleanupEnabled($0)) }
        )
      )

      Toggle(
        "Include current app name in cleanup prompt",
        isOn: Binding(
          get: { store.hexSettings.transcriptCleanupAppContextEnabled },
          set: { store.send(.setTranscriptCleanupAppContextEnabled($0)) }
        )
      )
      Text("When enabled, Hex passes the app name and bundle ID captured at recording start into the local cleanup prompt.")
        .settingsCaption()

      CleanupModelView(store: store.scope(state: \.cleanupModel, action: \.cleanupModel))
    }
    .enableInjection()
  }
}

private struct CleanupModelView: View {
  @ObserveInjection var inject
  @Bindable var store: StoreOf<CleanupModelFeature>

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      ForEach(store.models) { model in
        CleanupModelRow(
          model: model,
          isSelected: store.selectedModelID == model.internalName,
          isDownloading: store.isDownloading && store.downloadingModelID == model.internalName,
          downloadProgress: store.downloadProgress,
          onSelect: { store.send(.selectModel(model.internalName)) },
          onDownload: { store.send(.downloadModel(model.internalName)) },
          onDelete: { store.send(.deleteModel(model.internalName)) },
          onShowInFinder: { store.send(.openModelLocation(model.internalName)) }
        )
      }

      if let error = store.downloadError {
        Text(error)
          .font(.caption)
          .foregroundStyle(.red)
      }
    }
    .task { store.send(.task) }
    .enableInjection()
  }
}

private struct CleanupModelRow: View {
  let model: CleanupModelInfo
  let isSelected: Bool
  let isDownloading: Bool
  let downloadProgress: Double
  let onSelect: () -> Void
  let onDownload: () -> Void
  let onDelete: () -> Void
  let onShowInFinder: () -> Void

  var body: some View {
    HStack(spacing: 12) {
      Button(action: onSelect) {
        Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
      }
      .buttonStyle(.plain)

      VStack(alignment: .leading, spacing: 4) {
        HStack(spacing: 8) {
          Text(model.displayName)
            .font(.body.weight(.medium))
          if model.isDownloaded {
            Image(systemName: "checkmark.circle.fill")
              .foregroundStyle(.green)
          }
        }
        Text("\(model.size) · \(model.storageSize) · Local cleanup")
          .settingsCaption()
        if isDownloading {
          ProgressView(value: downloadProgress)
            .progressViewStyle(.linear)
        }
      }

      Spacer()

      if model.isDownloaded {
        Menu {
          Button("Show in Finder", action: onShowInFinder)
          Button("Delete", role: .destructive, action: onDelete)
        } label: {
          Image(systemName: "ellipsis.circle")
        }
        .menuStyle(.button)
        .buttonStyle(.borderless)
      } else if isDownloading {
        Text("\(Int(downloadProgress * 100))%")
          .font(.caption)
          .foregroundStyle(.secondary)
      } else {
        Button("Download", action: onDownload)
          .controlSize(.small)
      }
    }
    .padding(10)
    .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
  }
}
