import SwiftUI
import UIKit

/// A value that has to leave the screen accurately — ported from `BillsCaptureTest`
/// (`dev/iOs_Test`), which needed this for the exact same reason this app now does: comparing a
/// copied bundle ID against what gets registered in Google Cloud Console is one mistaken
/// character away from a broken OAuth client (plan §4.4).
struct CopyableRow: View {
    let label: String
    let value: String

    private static let confirmationDuration = Duration.seconds(2)

    @State private var didCopy = false

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.footnote.monospaced())
                    .textSelection(.enabled)
            }

            Spacer(minLength: 12)

            Button(action: copy) {
                Image(systemName: didCopy ? "checkmark.circle.fill" : "doc.on.doc")
                    .foregroundStyle(didCopy ? Color.green : Color.accentColor)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Copy \(label)")
        }
    }

    private func copy() {
        UIPasteboard.general.string = value
        didCopy = true

        Task {
            try? await Task.sleep(for: Self.confirmationDuration)
            didCopy = false
        }
    }
}
