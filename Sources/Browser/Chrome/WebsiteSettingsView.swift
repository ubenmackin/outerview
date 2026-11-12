// Chrome — Per-domain website settings sheet for the page menu.
import SwiftUI

@MainActor
public struct WebsiteSettingsView: View {
    public let host: String
    public let store: WebsiteSettingsStore
    public var onSettingsChanged: ((WebsiteSettings) -> Void)?
    public var onDone: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var settings: WebsiteSettings

    public init(
        host: String,
        store: WebsiteSettingsStore,
        onSettingsChanged: ((WebsiteSettings) -> Void)? = nil,
        onDone: (() -> Void)? = nil
    ) {
        self.host = host
        self.store = store
        self.onSettingsChanged = onSettingsChanged
        self.onDone = onDone
        _settings = State(initialValue: store.settings(forHost: host))
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Request Desktop Website", isOn: $settings.requestDesktopWebsite)
                    Toggle("Use Reader Automatically", isOn: $settings.useReaderAutomatically)
                } header: {
                    Text("While viewing \(host)")
                        .textCase(nil)
                }
            }
            .navigationTitle("Settings for \(host)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        handleDone()
                    } label: {
                        ZStack {
                            Circle()
                                .fill(Color.blue)
                                .frame(width: 32, height: 32)
                            Image(systemName: "checkmark")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
                    .accessibilityLabel("Done")
                }
            }
            .onChange(of: settings) { _, newSettings in
                store.updateSettings(newSettings, forHost: host)
                onSettingsChanged?(newSettings)
            }
        }
    }

    private func handleDone() {
        if let onDone {
            onDone()
        } else {
            dismiss()
        }
    }
}
