import SwiftUI

/// §4.4's one-time folder picker — iOS's own native equivalent to Android's
/// `FolderPickerScreen.kt`, deliberately **not** a ported WebView/JS Google Picker embed.
/// Android's own kdoc flags that version as "the single most fragile piece of §4.4's Drive
/// wiring" — a real origin/`postMessage` bug had to be diagnosed and fixed live on-device. A
/// plain SwiftUI list browser over the already-built `DriveAPI.listSubfolders` sidesteps that
/// whole bug class rather than porting it, at the cost of being a little more tapping for a
/// deeply nested folder — an acceptable trade for a screen used once.
struct FolderPickerView: View {
    let onPicked: () -> Void

    var body: some View {
        NavigationStack {
            FolderBrowserView(folderID: "root", folderName: "My Drive", onPicked: onPicked)
        }
    }
}

/// One level of the browse — recurses into itself via `NavigationLink` as the user drills in.
/// Drive's own convention: the synthetic id `"root"` addresses "My Drive" itself, not a real
/// folder id, so the top-level `FolderPickerView` above can pass it through unchanged.
private struct FolderBrowserView: View {
    @EnvironmentObject private var driveAuth: DriveAuthStore
    @EnvironmentObject private var folderPreferences: DriveFolderPreferences

    let folderID: String
    let folderName: String
    let onPicked: () -> Void

    @State private var subfolders: [DriveFolder] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    private let driveAPI: DriveAPI = RealDriveAPI()

    var body: some View {
        List {
            if isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
            } else if let errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            } else if subfolders.isEmpty {
                Text("No subfolders here.").foregroundStyle(.secondary)
            } else {
                ForEach(subfolders, id: \.id) { folder in
                    NavigationLink(folder.name) {
                        FolderBrowserView(folderID: folder.id, folderName: folder.name, onPicked: onPicked)
                    }
                }
            }
        }
        .navigationTitle(folderName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Use this folder") { pick() }
            }
        }
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            let token = try await driveAuth.validAccessToken()
            subfolders = try await driveAPI
                .listSubfolders(accessToken: token, parentFolderID: folderID)
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func pick() {
        folderPreferences.setScansFolder(DriveFolder(id: folderID, name: folderName))
        onPicked()
    }
}
