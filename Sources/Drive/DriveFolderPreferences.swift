import Foundation

/// The `Scans/` root folder chosen once via `FolderPickerView` — persists across launches so
/// every later Drive operation (folder listing for fuzzy-matching, uploads, `Rules_Learned.json`)
/// has it without re-picking. `UserDefaults`, not Keychain: this is a folder id/name, not a
/// credential, matching `BillCapturePreferences`'s own precedent.
///
/// Android's counterpart is `DriveFolderPreferences.kt` + a separate `DriveFolderState` reactive
/// wrapper around it — combined into one `ObservableObject` here since SwiftUI's environment-object
/// model doesn't need Android's two-type split (a plain `SharedPreferences` read isn't observable
/// on its own; `@Published` already is).
@MainActor
final class DriveFolderPreferences: ObservableObject {
    @Published private(set) var scansFolder: DriveFolder?

    private static let idKey = "drive_scans_folder_id"
    private static let nameKey = "drive_scans_folder_name"

    init() {
        scansFolder = Self.load()
    }

    func setScansFolder(_ folder: DriveFolder) {
        UserDefaults.standard.set(folder.id, forKey: Self.idKey)
        UserDefaults.standard.set(folder.name, forKey: Self.nameKey)
        scansFolder = folder
    }

    private static func load() -> DriveFolder? {
        guard
            let id = UserDefaults.standard.string(forKey: idKey),
            let name = UserDefaults.standard.string(forKey: nameKey)
        else { return nil }
        return DriveFolder(id: id, name: name)
    }
}
