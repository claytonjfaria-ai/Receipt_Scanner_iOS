import SwiftUI

/// §4.7's redaction editor — a port of Android `Receipt_Scanner`'s `RedactionEditorFullScreen` +
/// `RedactionPageCanvas`. Its own near-fullscreen screen rather than a section squeezed into the
/// normal Review layout, for the same reason Android's own kdoc gives: with Company/Amount/Billing
/// date also on screen, the page image shrinks to a cramped strip too small to place a box
/// accurately, and there's no always-visible way to finish. Company/amount/date don't matter while
/// redacting, so this screen shows nothing but the image, the page navigator, and Undo.
struct RedactionEditorView: View {
    let pdfURL: URL
    let pageCount: Int
    @Binding var currentPage: Int
    @Binding var regions: [RedactionRegion]
    let onDone: () -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text("Draw a box over anything sensitive, like a full account number — it's blacked out of the archived file before it's uploaded. Tap a marked box, or Undo, to remove it.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                if pageCount > 1 {
                    HStack(spacing: 16) {
                        Button("‹ Prev") { currentPage = max(0, currentPage - 1) }
                            .disabled(currentPage <= 0)
                        Text("Page \(currentPage + 1) of \(pageCount)")
                            .font(.subheadline)
                        Button("Next ›") { currentPage = min(pageCount - 1, currentPage + 1) }
                            .disabled(currentPage >= pageCount - 1)
                    }
                }

                // The remaining space goes entirely to the page image -- everything else here is
                // a couple of lines, so this is what actually benefits from the fullscreen mode.
                RedactionPageCanvasView(
                    pdfURL: pdfURL,
                    page: currentPage,
                    regionsOnPage: regions.filter { $0.page == currentPage },
                    onRegionDrawn: { rect in regions.append(RedactionRegion(page: currentPage, rect: rect)) },
                    onRegionRemoved: { region in regions.removeAll { $0 == region } }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                // A drag easily lands in the wrong spot on a first try -- a fast, always-visible
                // way to back it out rather than relying only on precisely tapping a box that can
                // be a thin strip. Removes the most recently drawn region across *any* page, not
                // just the one currently showing -- that's the one the user just placed.
                Button("Undo last box") { if !regions.isEmpty { regions.removeLast() } }
                    .disabled(regions.isEmpty)
            }
            .padding()
            .navigationTitle("Redact sensitive info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Top, not bottom -- must stay reachable without scrolling no matter how the page
                // image is sized, mirroring Android's own device-tested reasoning for this exact
                // placement (2026-08-22, see PdfRedactor's kdoc history).
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { onDone() }
                }
            }
        }
    }
}

/// Shows one rendered page with its already-confirmed regions overlaid, plus a drag gesture that
/// adds a new region. **v1 scope, same as Android:** existing boxes are accept-as-is or
/// tap-to-remove-and-redraw — no drag-to-resize/reposition of an already-placed box.
private struct RedactionPageCanvasView: View {
    let pdfURL: URL
    let page: Int
    let regionsOnPage: [RedactionRegion]
    let onRegionDrawn: (NormalizedRect) -> Void
    let onRegionRemoved: (RedactionRegion) -> Void

    @State private var image: UIImage?
    @State private var dragStart: CGPoint?
    @State private var dragCurrent: CGPoint?

    /// Points, not pixels -- SwiftUI drag locations are already in the fitted view's own point
    /// space, so this is a direct translation of Android's 24px minimum, not a physical-unit
    /// match. Same purpose either way: too small to be an intentional box.
    private let minDragPoints: CGFloat = 24

    var body: some View {
        GeometryReader { geometry in
            Group {
                if let image {
                    let fitted = fittedSize(for: image.size, in: geometry.size)
                    ZStack(alignment: .topLeading) {
                        Image(uiImage: image)
                            .resizable()
                            .frame(width: fitted.width, height: fitted.height)

                        ForEach(regionsOnPage, id: \.self) { region in
                            let rect = region.rect
                            Rectangle()
                                .fill(Color.black)
                                .frame(width: fitted.width * rect.width, height: fitted.height * rect.height)
                                .position(
                                    x: fitted.width * (rect.x + rect.width / 2),
                                    y: fitted.height * (rect.y + rect.height / 2)
                                )
                                .onTapGesture { onRegionRemoved(region) }
                        }

                        if let dragStart, let dragCurrent {
                            let live = liveRect(from: dragStart, to: dragCurrent)
                            Rectangle()
                                .fill(Color.black.opacity(0.5))
                                .frame(width: live.width, height: live.height)
                                .position(x: live.midX, y: live.midY)
                                .allowsHitTesting(false)
                        }
                    }
                    .frame(width: fitted.width, height: fitted.height)
                    .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                    .contentShape(Rectangle())
                    // Scoped to exactly the fitted image rect (this view's own frame, unaffected
                    // by where `.position` renders it in the parent) -- a drag in the letterbox
                    // margin can't produce a region outside the actual page.
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                if dragStart == nil { dragStart = value.startLocation }
                                dragCurrent = value.location
                            }
                            .onEnded { value in
                                let start = dragStart
                                dragStart = nil
                                dragCurrent = nil
                                guard let start else { return }
                                if let normalized = normalizedRect(from: start, to: value.location, in: fitted) {
                                    onRegionDrawn(normalized)
                                }
                            }
                    )
                } else {
                    ProgressView()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                }
            }
        }
        .task(id: page) { await load() }
    }

    private func load() async {
        image = nil
        image = try? await Task.detached(priority: .userInitiated) {
            try BillPageRenderer.renderPage(of: pdfURL, page: page, dpi: BillPageRenderer.previewDPI)
        }.value
    }

    private func fittedSize(for imageSize: CGSize, in containerSize: CGSize) -> CGSize {
        guard imageSize.width > 0, imageSize.height > 0, containerSize.width > 0, containerSize.height > 0 else { return .zero }
        let imageAspect = imageSize.width / imageSize.height
        if containerSize.width / containerSize.height > imageAspect {
            let height = containerSize.height
            return CGSize(width: height * imageAspect, height: height)
        } else {
            let width = containerSize.width
            return CGSize(width: width, height: width / imageAspect)
        }
    }

    private func liveRect(from start: CGPoint, to current: CGPoint) -> CGRect {
        CGRect(
            x: min(start.x, current.x),
            y: min(start.y, current.y),
            width: abs(current.x - start.x),
            height: abs(current.y - start.y)
        )
    }

    private func normalizedRect(from start: CGPoint, to end: CGPoint, in container: CGSize) -> NormalizedRect? {
        guard container.width > 0, container.height > 0 else { return nil }
        let left = clamp(min(start.x, end.x), 0, container.width)
        let top = clamp(min(start.y, end.y), 0, container.height)
        let right = clamp(max(start.x, end.x), 0, container.width)
        let bottom = clamp(max(start.y, end.y), 0, container.height)
        guard right - left >= minDragPoints, bottom - top >= minDragPoints else { return nil } // Too small to be an intentional box.

        let x = left / container.width
        let y = top / container.height
        return NormalizedRect(
            x: x,
            y: y,
            width: min((right - left) / container.width, 1 - x),
            height: min((bottom - top) / container.height, 1 - y)
        )
    }

    private func clamp(_ value: CGFloat, _ lower: CGFloat, _ upper: CGFloat) -> CGFloat {
        min(max(value, lower), upper)
    }
}
