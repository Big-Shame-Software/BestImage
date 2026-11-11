import ImageIO
import SwiftUI
import UniformTypeIdentifiers

/// Crop an image, auto-detect its subject on a transparent or white background, and save a
/// cutout copy. Brushes let you restore background that was removed by mistake (the white
/// dress on a white poster) or erase what was left behind.
/// Color behind the cutout preview and loupes. Green makes a removed background obvious.
enum Backdrop: String, CaseIterable, Identifiable {
    case white = "White"
    case green = "Green"
    case black = "Black"

    var id: String { rawValue }

    /// Components in 0–255.
    var rgb: (r: Int, g: Int, b: Int) {
        switch self {
        case .white: (255, 255, 255)
        case .green: (0, 230, 51)
        case .black: (0, 0, 0)
        }
    }

    var color: Color {
        Color(red: Double(rgb.r) / 255, green: Double(rgb.g) / 255, blue: Double(rgb.b) / 255)
    }
}

struct CropSheet: View {
    let job: ImageJob
    let onSaved: (URL) -> Void
    let close: () -> Void

    private enum Mode: String, CaseIterable, Identifiable {
        case crop = "Crop"
        case restore = "Restore"
        case erase = "Erase"
        var id: String { rawValue }
    }

    private enum Corner: CaseIterable {
        case topLeft, topRight, bottomLeft, bottomRight
    }

    @State private var source: CGImage?
    @State private var analysis: CutoutDetector.Analysis?
    /// One byte per pixel: 0 = automatic, 1 = restored with the brush, 2 = erased.
    @State private var overrides: [UInt8] = []
    @State private var preview: CGImage?
    @State private var cropRect = CGRect.zero
    @State private var rectIsManual = false
    @State private var showCutout = true
    /// Display zoom relative to "fit to window". The canvas scrolls when zoomed in.
    @State private var zoom: Double = 1
    @State private var shadowLevel = Double(CutoutDetector.defaultShadowLevel)
    @State private var analysisTask: Task<Void, Never>?
    @State private var mode: Mode = .crop
    /// Brush radius in on-screen points, converted to image pixels when painting.
    @State private var brushRadius: Double = 22
    @State private var statusText = "Loading…"
    @State private var isWorking = false
    @State private var errorText: String?
    @State private var suggestions: [TrimSuggestion] = []
    @State private var isSuggesting = false
    @State private var trimBackground: TrimBackground = .auto
    @State private var edgeStep = 1
    @State private var loupeZoom: CGFloat = 6
    @State private var splitting = false
    @State private var backdrop: Backdrop = .green
    /// The edge the user adjusted most recently; its color is shown in the meter.
    @State private var lastEdge: Side?
    /// Boxes for split mode, in image pixels. `cropRect` mirrors the selected box.
    @State private var boxes: [CGRect] = []
    @State private var selectedBox = 0

    private enum Side: CaseIterable {
        case top, bottom, left, right

        var label: String {
            switch self {
            case .top: "Top"
            case .bottom: "Bottom"
            case .left: "Left"
            case .right: "Right"
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Crop & Cut Out").font(.title2.weight(.semibold))
            Text(job.currentURL.lastPathComponent)
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(alignment: .top, spacing: 14) {
                canvas
                    .frame(minHeight: 420, maxHeight: .infinity)
                    .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                sidebar
                    .frame(width: 300)
                    .frame(maxHeight: .infinity)
            }

            controls

            HStack {
                Text(errorText ?? statusText)
                    .font(.caption)
                    .foregroundStyle(errorText == nil ? Color.secondary : Color.red)
                    .lineLimit(2)
                Spacer()
                Button("Cancel") { close() }
                    .keyboardShortcut(.cancelAction)
                Button(saveTitle, action: performSave)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(source == nil || isWorking)
            }
        }
        .padding(20)
        .frame(minWidth: 960, maxWidth: .infinity, minHeight: 640, maxHeight: .infinity, alignment: .topLeading)
        .task { await load() }
        .onChange(of: shadowLevel) { _, _ in scheduleAnalysis() }
        .onChange(of: cropRect) { _, newRect in
            if splitting, boxes.indices.contains(selectedBox) { boxes[selectedBox] = newRect }
        }
        .onChange(of: splitting) { _, isOn in
            guard isOn else { return }
            if boxes.isEmpty { boxes = proposeBoxes() }
            selectBox(min(selectedBox, max(0, boxes.count - 1)))
        }
    }

    // MARK: - Layout

    private var canvas: some View {
        GeometryReader { geo in
            if let source {
                let fit = fittedSize(source, in: geo.size)
                let size = CGSize(width: fit.width * zoom, height: fit.height * zoom)
                let scale = size.width / CGFloat(source.width)
                let shown = showCutout ? (preview ?? source) : source
                ScrollView([.horizontal, .vertical]) {
                    ZStack(alignment: .topLeading) {
                        if showCutout { backdrop.color }
                        Image(decorative: shown, scale: 1)
                            .resizable()
                            .interpolation(.high)
                            .frame(width: size.width, height: size.height)

                        dimming(scale: scale)

                        if mode == .crop || splitting {
                            ForEach(Corner.allCases, id: \.self) { corner in
                                handle(corner, scale: scale)
                            }
                        } else {
                            brushSurface(scale: scale)
                        }
                    }
                    .frame(width: size.width, height: size.height)
                    .coordinateSpace(name: "image")
                    // Centers the image when it is smaller than the window.
                    .frame(width: max(size.width, geo.size.width), height: max(size.height, geo.size.height))
                }
            } else if let errorText {
                Text(errorText).foregroundStyle(.red)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func dimming(scale: CGFloat) -> some View {
        Canvas { context, size in
            if splitting {
                for (index, box) in boxes.enumerated() {
                    let rect = CGRect(
                        x: box.minX * scale,
                        y: box.minY * scale,
                        width: box.width * scale,
                        height: box.height * scale
                    )
                    let isSelected = index == selectedBox
                    let color: Color = isSelected ? .yellow : .white
                    context.stroke(Path(rect), with: .color(color), lineWidth: isSelected ? 2.5 : 1.5)
                    context.draw(
                        Text("\(index + 1)").font(.caption.bold()).foregroundColor(color),
                        at: CGPoint(x: rect.minX + 12, y: rect.minY + 12)
                    )
                }
                return
            }
            let rect = CGRect(
                x: cropRect.minX * scale,
                y: cropRect.minY * scale,
                width: cropRect.width * scale,
                height: cropRect.height * scale
            )
            var path = Path(CGRect(origin: .zero, size: size))
            path.addRect(rect)
            context.fill(path, with: .color(.black.opacity(0.5)), style: FillStyle(eoFill: true))
            context.stroke(Path(rect), with: .color(.white), lineWidth: 1.5)
        }
        .allowsHitTesting(false)
    }

    private func handle(_ corner: Corner, scale: CGFloat) -> some View {
        let point = cornerPoint(corner, scale: scale)
        return Circle()
            .fill(.white)
            .overlay(Circle().stroke(.black.opacity(0.6), lineWidth: 1))
            .frame(width: 14, height: 14)
            .frame(width: 32, height: 32)
            .contentShape(Rectangle())
            .position(point)
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named("image"))
                    .onChanged { value in
                        moveCorner(corner, to: CGPoint(x: value.location.x / scale, y: value.location.y / scale))
                    }
            )
    }

    private func brushSurface(scale: CGFloat) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named("image"))
                    .onChanged { value in
                        paint(at: CGPoint(x: value.location.x / scale, y: value.location.y / scale), scale: scale)
                    }
                    .onEnded { _ in refreshPreview() }
            )
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button("Auto-Detect", action: autoDetect)
                    .disabled(analysis == nil || isWorking)
                Button { zoom = max(1, zoom / 1.5) } label: { Image(systemName: "minus.magnifyingglass") }
                    .help("Zoom out")
                    .disabled(zoom <= 1)
                Slider(value: $zoom, in: 1...8)
                    .frame(width: 140)
                Button { zoom = min(8, zoom * 1.5) } label: { Image(systemName: "plus.magnifyingglass") }
                    .help("Zoom in")
                    .disabled(zoom >= 8)
                Button("Fit") { zoom = 1 }
                    .disabled(zoom == 1)
                Button("Full Image") {
                    guard let source else { return }
                    cropRect = CGRect(x: 0, y: 0, width: source.width, height: source.height)
                    rectIsManual = true
                }
                .disabled(source == nil)
                Spacer()
                Toggle("Cut out background", isOn: $showCutout)
                    .toggleStyle(.switch)
                    .disabled(analysis?.background == CutoutDetector.Background.none)
                Picker("Backdrop", selection: $backdrop) {
                    ForEach(Backdrop.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 210)
                .disabled(!showCutout)
            }

            HStack {
                Picker("Tool", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(width: 240)
                .disabled(source == nil)

                Text("Brush").font(.callout).foregroundStyle(.secondary)
                Slider(value: $brushRadius, in: 4...120)
                    .frame(width: 180)
                    .disabled(mode == .crop)
                Button("Reset Brushes") {
                    overrides = [UInt8](repeating: 0, count: overrides.count)
                    refreshPreview()
                }
                .disabled(!overrides.contains { $0 != 0 })
            }

            HStack {
                Text("Shadow cutoff").font(.callout).foregroundStyle(.secondary)
                Slider(value: $shadowLevel, in: Double(CutoutDetector.shadowLevelRange.lowerBound)...Double(CutoutDetector.shadowLevelRange.upperBound), step: 1)
                    .frame(width: 260)
                Text("\(Int(shadowLevel))")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                Text("Lower removes more gray.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Work

    private func load() async {
        let url = job.currentURL
        let image: CGImage? = await Task.detached(priority: .userInitiated) {
            guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
            return CGImageSourceCreateImageAtIndex(imageSource, 0, nil)
        }.value

        guard let image else {
            errorText = "Could not open this image."
            return
        }
        source = image
        cropRect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        await runAnalysis(image)
    }

    private func scheduleAnalysis() {
        analysisTask?.cancel()
        analysisTask = Task {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled, let source else { return }
            await runAnalysis(source)
        }
    }

    private func runAnalysis(_ image: CGImage) async {
        isWorking = true
        statusText = "Finding the subject…"
        let level = Int(shadowLevel)
        let result = await Task.detached(priority: .userInitiated) {
            CutoutDetector.analyze(image, shadowLevel: level)
        }.value
        isWorking = false

        guard let result else {
            errorText = "Could not analyze this image."
            return
        }
        analysis = result
        if overrides.count != result.width * result.height {
            overrides = [UInt8](repeating: 0, count: result.width * result.height)
        }
        if !rectIsManual { cropRect = result.subjectBounds }
        refreshPreview()
        statusText = describe(result.background)
    }

    private func autoDetect() {
        guard let analysis else { return }
        overrides = [UInt8](repeating: 0, count: analysis.width * analysis.height)
        cropRect = analysis.subjectBounds
        rectIsManual = false
        refreshPreview()
        statusText = describe(analysis.background)
    }

    // MARK: - Color meter

    /// Average color of the 1px line just inside `side` of the crop, composited over the
    /// backdrop, so it matches what is on screen.
    private func edgeReading(_ side: Side) -> (r: Int, g: Int, b: Int)? {
        guard let source else { return nil }
        let image = showCutout ? (preview ?? source) : source
        let rect = cropRect.integral
        let line: CGRect
        switch side {
        case .top: line = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: 1)
        case .bottom: line = CGRect(x: rect.minX, y: rect.maxY - 1, width: rect.width, height: 1)
        case .left: line = CGRect(x: rect.minX, y: rect.minY, width: 1, height: rect.height)
        case .right: line = CGRect(x: rect.maxX - 1, y: rect.minY, width: 1, height: rect.height)
        }
        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let clipped = line.intersection(bounds).integral
        guard !clipped.isEmpty, let strip = image.cropping(to: clipped) else { return nil }

        let width = strip.width
        let height = strip.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = bytes.withUnsafeMutableBytes { raw -> Bool in
            guard let context = CGContext(
                data: raw.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(strip, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }

        let backdropRGB = backdrop.rgb
        var sums = (r: 0, g: 0, b: 0)
        let count = width * height
        for i in 0..<count {
            let o = i * 4
            // Premultiplied color plus the backdrop showing through the transparent part.
            let showing = 255 - Int(bytes[o + 3])
            sums.r += Int(bytes[o]) + backdropRGB.r * showing / 255
            sums.g += Int(bytes[o + 1]) + backdropRGB.g * showing / 255
            sums.b += Int(bytes[o + 2]) + backdropRGB.b * showing / 255
        }
        return (sums.r / count, sums.g / count, sums.b / count)
    }

    /// Name of the closest color in BSSBrand or the backdrop choices. Exact-ish matches
    /// (within 12 RGB units) get the plain name; anything else reports the nearest one.
    private func colorName(r: Int, g: Int, b: Int) -> String? {
        var candidates: [(name: String, hex: UInt32)] = BSSBrand.namedHex
        for option in Backdrop.allCases {
            let c = option.rgb
            candidates.append(("Backdrop \(option.rawValue)", UInt32(c.r) << 16 | UInt32(c.g) << 8 | UInt32(c.b)))
        }
        let nearest = candidates.map { entry -> (name: String, distance: Double) in
            let er = Int((entry.hex >> 16) & 0xFF)
            let eg = Int((entry.hex >> 8) & 0xFF)
            let eb = Int(entry.hex & 0xFF)
            let dr = Double(r - er), dg = Double(g - eg), db = Double(b - eb)
            return (entry.name, (dr * dr + dg * dg + db * db).squareRoot())
        }.min { $0.distance < $1.distance }
        guard let nearest else { return nil }
        return nearest.distance <= 12
            ? "Named: \(nearest.name)"
            : "Nearest named: \(nearest.name) (off by \(Int(nearest.distance.rounded())))"
    }

    private func edgeMeter(_ side: Side) -> some View {
        let reading = edgeReading(side)
        return HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 6)
                .fill(reading.map { Color(red: Double($0.r) / 255, green: Double($0.g) / 255, blue: Double($0.b) / 255) } ?? Color.clear)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.gray.opacity(0.5), lineWidth: 1))
                .frame(width: 46, height: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(side.label) edge")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let reading {
                    Text("R \(reading.r)  G \(reading.g)  B \(reading.b)")
                        .font(.callout.monospacedDigit())
                    Text(String(format: "#%02X%02X%02X", reading.r, reading.g, reading.b))
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                    if let name = colorName(r: reading.r, g: reading.g, b: reading.b) {
                        Text(name)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("No pixels on this edge")
                        .font(.caption)
                }
            }
        }
    }

    // MARK: - Save routing

    private var saveTitle: String {
        splitting && boxes.count > 1 ? "Save \(boxes.count) Copies" : "Save Copy"
    }

    private func performSave() {
        if splitting && boxes.count > 1 {
            saveAll()
        } else {
            save()
        }
    }

    // MARK: - Split helpers

    private func proposeBoxes() -> [CGRect] {
        guard let source else { return [] }
        return PosterSplitter.propose(source)
    }

    private func reproposeBoxes() {
        boxes = proposeBoxes()
        selectBox(0)
    }

    private func selectBox(_ index: Int) {
        guard boxes.indices.contains(index) else { return }
        selectedBox = index
        cropRect = boxes[index]
        rectIsManual = true
    }

    private func addBox() {
        guard let source else { return }
        let width = CGFloat(source.width) * 0.3
        let height = CGFloat(source.height) * 0.3
        boxes.append(CGRect(
            x: (CGFloat(source.width) - width) / 2,
            y: (CGFloat(source.height) - height) / 2,
            width: width,
            height: height
        ))
        selectBox(boxes.count - 1)
    }

    private func deleteBox() {
        guard boxes.indices.contains(selectedBox) else { return }
        boxes.remove(at: selectedBox)
        selectBox(min(selectedBox, boxes.count - 1))
    }

    private func saveAll() {
        guard let analysis, let source, !boxes.isEmpty else { return }
        let bounds = CGRect(x: 0, y: 0, width: source.width, height: source.height)
        let base = showCutout ? (analysis.cutout(overrides: overrides) ?? source) : source
        let directory = job.currentURL.deletingLastPathComponent()
        let stem = URL(fileURLWithPath: job.originalName).deletingPathExtension().lastPathComponent
            + (showCutout ? "-cutout" : "-crop")
        var usedNames = Set(((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? [])
            .map { $0.precomposedStringWithCanonicalMapping.lowercased() })

        var outputs: [(image: CGImage, url: URL)] = []
        for (index, box) in boxes.enumerated() {
            let rect = box.integral.intersection(bounds)
            guard rect.width >= 1, rect.height >= 1, let cropped = base.cropping(to: rect) else { continue }
            let name = ScoreFilename.uniqueName(preferred: "\(stem)-\(index + 1).png", usedNames: &usedNames)
            outputs.append((cropped, directory.appendingPathComponent(name)))
        }
        guard !outputs.isEmpty else {
            errorText = "No box has a valid area."
            return
        }

        isWorking = true
        errorText = nil
        statusText = "Saving \(outputs.count) images…"
        let toWrite = outputs
        Task {
            let written = await Task.detached(priority: .userInitiated) {
                toWrite.compactMap { Self.writePNG($0.image, to: $0.url) ? $0.url : nil }
            }.value
            isWorking = false
            for url in written { onSaved(url) }
            if written.count == toWrite.count {
                close()
            } else {
                errorText = "Saved \(written.count) of \(toWrite.count) images."
            }
        }
    }

    private func refreshPreview() {
        preview = analysis?.cutout(overrides: overrides)
    }

    private func moveCorner(_ corner: Corner, to point: CGPoint) {
        guard let source else { return }
        let minSize: CGFloat = 8
        let width = CGFloat(source.width)
        let height = CGFloat(source.height)
        var x0 = cropRect.minX, x1 = cropRect.maxX
        var y0 = cropRect.minY, y1 = cropRect.maxY

        switch corner {
        case .topLeft:
            x0 = min(max(point.x, 0), x1 - minSize)
            y0 = min(max(point.y, 0), y1 - minSize)
        case .topRight:
            x1 = max(min(point.x, width), x0 + minSize)
            y0 = min(max(point.y, 0), y1 - minSize)
        case .bottomLeft:
            x0 = min(max(point.x, 0), x1 - minSize)
            y1 = max(min(point.y, height), y0 + minSize)
        case .bottomRight:
            x1 = max(min(point.x, width), x0 + minSize)
            y1 = max(min(point.y, height), y0 + minSize)
        }
        cropRect = CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
        rectIsManual = true
    }

    private func paint(at point: CGPoint, scale: CGFloat) {
        guard let analysis, overrides.count == analysis.width * analysis.height else { return }
        let radius = CGFloat(brushRadius) / scale
        let value: UInt8 = mode == .restore ? 1 : 2
        let minX = max(0, Int(floor(point.x - radius)))
        let maxX = min(analysis.width - 1, Int(ceil(point.x + radius)))
        let minY = max(0, Int(floor(point.y - radius)))
        let maxY = min(analysis.height - 1, Int(ceil(point.y + radius)))
        guard minX <= maxX, minY <= maxY else { return }

        for y in minY...maxY {
            for x in minX...maxX {
                let dx = CGFloat(x) + 0.5 - point.x
                let dy = CGFloat(y) + 0.5 - point.y
                if dx * dx + dy * dy <= radius * radius {
                    overrides[y * analysis.width + x] = value
                }
            }
        }
    }

    private func save() {
        guard let analysis, let source else { return }
        let bounds = CGRect(x: 0, y: 0, width: source.width, height: source.height)
        let rect = cropRect.integral.intersection(bounds)
        guard rect.width >= 1, rect.height >= 1 else {
            errorText = "The crop area is empty."
            return
        }

        let base = showCutout ? (analysis.cutout(overrides: overrides) ?? source) : source
        guard let cropped = base.cropping(to: rect) else {
            errorText = "Could not crop this image."
            return
        }

        let directory = job.currentURL.deletingLastPathComponent()
        let stem = URL(fileURLWithPath: job.originalName).deletingPathExtension().lastPathComponent
            + (showCutout ? "-cutout" : "-crop")
        var usedNames = Set(((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? [])
            .map { $0.precomposedStringWithCanonicalMapping.lowercased() })
        let name = ScoreFilename.uniqueName(preferred: stem + ".png", usedNames: &usedNames)
        let destination = directory.appendingPathComponent(name)

        isWorking = true
        errorText = nil
        statusText = "Saving…"
        Task {
            let written = await Task.detached(priority: .userInitiated) {
                Self.writePNG(cropped, to: destination)
            }.value
            isWorking = false
            if written {
                onSaved(destination)
                close()
            } else {
                errorText = "Could not save the copy."
            }
        }
    }

    // MARK: - Sidebar: suggestions and edge controls

    private var sidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                GroupBox("Split sheet") {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Split into separate images", isOn: $splitting)
                            .disabled(source == nil)
                        if splitting {
                            Text("Adjust each numbered box, then save them all.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            HStack {
                                ForEach(boxes.indices, id: \.self) { index in
                                    Button("\(index + 1)") { selectBox(index) }
                                        .buttonStyle(.borderedProminent)
                                        .tint(index == selectedBox ? .accentColor : .gray)
                                        .controlSize(.small)
                                }
                            }
                            HStack {
                                Button("Re-propose", action: reproposeBoxes)
                                Button("Add Box", action: addBox)
                                Button("Delete Box", action: deleteBox).disabled(boxes.isEmpty)
                            }
                            .controlSize(.small)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox("Suggested trims") {
                    VStack(alignment: .leading, spacing: 8) {
                        if ImageMagick.locate() != nil {
                            Picker("Background", selection: $trimBackground) {
                                ForEach(TrimBackground.allCases) { Text($0.rawValue).tag($0) }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            .help("Auto reads the corner pixels. If nothing trims, force White or Black.")

                            Button(isSuggesting ? "Scanning…" : "Find Trims", action: findSuggestions)
                                .disabled(source == nil || isSuggesting)

                            ForEach(suggestions) { suggestion in
                                Button { apply(suggestion) } label: { suggestionCard(suggestion) }
                                    .buttonStyle(.plain)
                            }
                        } else {
                            Text("Fuzz-trim suggestions need ImageMagick. Install it with:")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("brew install imagemagick")
                                .font(.caption.monospaced())
                                .textSelection(.enabled)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox("Edges") {
                    VStack(alignment: .leading, spacing: 10) {
                        if let lastEdge {
                            edgeMeter(lastEdge)
                        } else {
                            Text("Adjust an edge to read its color.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if let source {
                            let rect = cropRect
                            loupeGrid(image: showCutout ? (preview ?? source) : source, rect: rect)
                            HStack {
                                Text("Zoom").font(.caption)
                                Slider(value: $loupeZoom, in: 2...16, step: 1)
                                Text("\(Int(loupeZoom))×").font(.caption).monospacedDigit()
                            }
                        }
                        Picker("Step", selection: $edgeStep) {
                            ForEach([1, 5, 10, 25], id: \.self) { Text("\($0) px").tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()

                        insetRow("Top", .top)
                        insetRow("Bottom", .bottom)
                        insetRow("Left", .left)
                        insetRow("Right", .right)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .disabled(source == nil)
            }
            .padding(.trailing, 4)
        }
    }

    private func suggestionCard(_ suggestion: TrimSuggestion) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Fuzz \(suggestion.fuzz)%").font(.callout.weight(.semibold))
                Text("\(Int(suggestion.size.width)) × \(Int(suggestion.size.height))")
                    .font(.caption)
                    .monospacedDigit()
                Text(String(format: "Removes up to %.0f%%", suggestion.removedPercent))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            switch suggestion.danger {
            case .none: EmptyView()
            case .warning:
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
                    .help("Removes more than 25% — check the result")
            case .severe:
                Image(systemName: "exclamationmark.octagon.fill").foregroundStyle(.red)
                    .help("Removes more than 40% — likely eating into the image")
            }
        }
        .padding(8)
        .background(.background, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: 8))
    }

    /// White behind the cutout, so semi-transparent edges show as a shadow against white.
    private var loupeBackdrop: Color { showCutout ? backdrop.color : .black }

    private func loupeGrid(image: CGImage, rect: CGRect) -> some View {
        Grid(horizontalSpacing: 6, verticalSpacing: 6) {
            GridRow {
                CornerLoupeView(title: "Top Left", image: image, corner: CGPoint(x: rect.minX, y: rect.minY), zoom: loupeZoom, backdrop: loupeBackdrop)
                CornerLoupeView(title: "Top", image: image, corner: CGPoint(x: rect.midX, y: rect.minY), zoom: loupeZoom, backdrop: loupeBackdrop)
                CornerLoupeView(title: "Top Right", image: image, corner: CGPoint(x: rect.maxX, y: rect.minY), zoom: loupeZoom, backdrop: loupeBackdrop)
            }
            GridRow {
                CornerLoupeView(title: "Left", image: image, corner: CGPoint(x: rect.minX, y: rect.midY), zoom: loupeZoom, backdrop: loupeBackdrop)
                Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                CornerLoupeView(title: "Right", image: image, corner: CGPoint(x: rect.maxX, y: rect.midY), zoom: loupeZoom, backdrop: loupeBackdrop)
            }
            GridRow {
                CornerLoupeView(title: "Bottom Left", image: image, corner: CGPoint(x: rect.minX, y: rect.maxY), zoom: loupeZoom, backdrop: loupeBackdrop)
                CornerLoupeView(title: "Bottom", image: image, corner: CGPoint(x: rect.midX, y: rect.maxY), zoom: loupeZoom, backdrop: loupeBackdrop)
                CornerLoupeView(title: "Bottom Right", image: image, corner: CGPoint(x: rect.maxX, y: rect.maxY), zoom: loupeZoom, backdrop: loupeBackdrop)
            }
        }
    }

    private func insetRow(_ label: String, _ side: Side) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.callout)
                .frame(width: 52, alignment: .leading)
            Button { adjust(side, by: -edgeStep) } label: { Image(systemName: "minus") }
            TextField("", value: Binding(
                get: { insetValue(side) },
                set: { setInset(side, to: $0) }
            ), format: .number)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.center)
                .monospacedDigit()
                .frame(width: 60)
            Button { adjust(side, by: edgeStep) } label: { Image(systemName: "plus") }
        }
        .buttonRepeatBehavior(.enabled)
    }

    private var currentInsets: ManualInsets? {
        guard let source else { return nil }
        return ManualInsets(rect: cropRect, imageSize: CGSize(width: source.width, height: source.height))
    }

    private func insetValue(_ side: Side) -> Int {
        guard let insets = currentInsets else { return 0 }
        switch side {
        case .top: return insets.top
        case .bottom: return insets.bottom
        case .left: return insets.left
        case .right: return insets.right
        }
    }

    private func setInset(_ side: Side, to value: Int) {
        guard let source, var insets = currentInsets else { return }
        switch side {
        case .top: insets.top = value
        case .bottom: insets.bottom = value
        case .left: insets.left = value
        case .right: insets.right = value
        }
        cropRect = insets.cropRect(in: CGSize(width: source.width, height: source.height))
        rectIsManual = true
        lastEdge = side
    }

    private func adjust(_ side: Side, by delta: Int) {
        setInset(side, to: max(0, insetValue(side) + delta))
    }

    private func apply(_ suggestion: TrimSuggestion) {
        cropRect = suggestion.cropRect
        rectIsManual = true
        statusText = "Using the fuzz \(suggestion.fuzz)% trim."
    }

    private func findSuggestions() {
        guard let magickPath = ImageMagick.locate() else { return }
        let url = job.currentURL
        let background = trimBackground
        let workDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BestImage-trim-\(UUID().uuidString)", isDirectory: true)
        isSuggesting = true
        errorText = nil
        statusText = "Scanning fuzz levels…"

        Task {
            defer { try? FileManager.default.removeItem(at: workDirectory) }
            do {
                let found = try await Task.detached(priority: .userInitiated) {
                    try FileManager.default.createDirectory(at: workDirectory, withIntermediateDirectories: true)
                    return try TrimSuggester.suggestions(
                        for: url,
                        background: background,
                        magickPath: magickPath,
                        workDirectory: workDirectory
                    )
                }.value
                suggestions = found
                statusText = found.isEmpty
                    ? "No trims found. Try another background."
                    : "\(found.count) trim suggestion\(found.count == 1 ? "" : "s"). Click one to use it."
            } catch {
                errorText = error.localizedDescription
            }
            isSuggesting = false
        }
    }

    // MARK: - Helpers

    private func fittedSize(_ image: CGImage, in container: CGSize) -> CGSize {
        let imageWidth = CGFloat(max(image.width, 1))
        let imageHeight = CGFloat(max(image.height, 1))
        let scale = min(container.width / imageWidth, container.height / imageHeight)
        return CGSize(width: imageWidth * scale, height: imageHeight * scale)
    }

    private func cornerPoint(_ corner: Corner, scale: CGFloat) -> CGPoint {
        let x = (corner == .topLeft || corner == .bottomLeft ? cropRect.minX : cropRect.maxX) * scale
        let y = (corner == .topLeft || corner == .topRight ? cropRect.minY : cropRect.maxY) * scale
        return CGPoint(x: x, y: y)
    }

    private func describe(_ background: CutoutDetector.Background) -> String {
        switch background {
        case .transparent: "Transparent background found. Cutout ready."
        case .white: "White background found. Cutout ready."
        case .none: "No transparent or white edge found, so only cropping is available."
        }
    }

    nonisolated private static func writePNG(_ image: CGImage, to url: URL) -> Bool {
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else { return false }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination)
    }
}


/// Magnified patch of the image centered on one crop corner, with a crosshair on the
/// exact edge pixel. Ported from BorderTrim.
struct CornerLoupeView: View {
    let title: String
    let image: CGImage
    let corner: CGPoint
    let zoom: CGFloat
    var backdrop: Color = .black

    private let paneHeight: CGFloat = 86

    var body: some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            GeometryReader { proxy in
                ZStack {
                    if let patch = makePatch(paneSize: proxy.size) {
                        Image(decorative: patch.image, scale: 1)
                            .resizable()
                            .interpolation(.none)
                            .frame(width: CGFloat(patch.image.width) * zoom,
                                   height: CGFloat(patch.image.height) * zoom)
                            .offset(x: patch.offset.x, y: patch.offset.y)
                    }
                    Path { p in
                        p.move(to: CGPoint(x: proxy.size.width / 2, y: 0))
                        p.addLine(to: CGPoint(x: proxy.size.width / 2, y: proxy.size.height))
                        p.move(to: CGPoint(x: 0, y: proxy.size.height / 2))
                        p.addLine(to: CGPoint(x: proxy.size.width, y: proxy.size.height / 2))
                    }
                    .stroke(Color.red.opacity(0.8), lineWidth: 1)
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
                .clipped()
            }
            .frame(height: paneHeight)
            .background(backdrop)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    private func makePatch(paneSize: CGSize) -> (image: CGImage, offset: CGPoint)? {
        let radiusX = ceil(paneSize.width / 2 / zoom) + 1
        let radiusY = ceil(paneSize.height / 2 / zoom) + 1
        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let rect = CGRect(
            x: corner.x - radiusX,
            y: corner.y - radiusY,
            width: radiusX * 2,
            height: radiusY * 2
        ).intersection(bounds).integral
        guard !rect.isEmpty, let patch = image.cropping(to: rect) else { return nil }

        let cornerInPatch = CGPoint(x: (corner.x - rect.minX) * zoom, y: (corner.y - rect.minY) * zoom)
        let patchCenter = CGPoint(x: CGFloat(patch.width) * zoom / 2, y: CGFloat(patch.height) * zoom / 2)
        return (patch, CGPoint(x: patchCenter.x - cornerInPatch.x, y: patchCenter.y - cornerInPatch.y))
    }
}
