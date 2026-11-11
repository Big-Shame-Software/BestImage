import SwiftUI

/// Branded About window (styleguide §9): publisher mark, category hero art,
/// starburst accent, attribution. Everything else is system type.
struct AboutView: View {
    @Environment(\.colorScheme) private var colorScheme

    static let shelf = "Photography"
    private let category = BSSBrand.Category.media

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "Version \(short) (\(build))"
    }

    var body: some View {
        VStack(spacing: 0) {
            BSSRainbowStripe()

            VStack(spacing: 14) {
                ZStack(alignment: .topTrailing) {
                    PixelDisk(size: 96)
                    Starburst(size: 30).offset(x: 26, y: -14)
                }
                .padding(.top, 8)

                VStack(spacing: 4) {
                    Text("BestImage")
                        .font(.title.weight(.semibold))
                    Text(version)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Text("Your photos, ranked. Try not to take it personally.")
                    .font(.body)
                    .multilineTextAlignment(.center)

                Text("Filed under: \(Self.shelf)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Image("BigShameLogo")
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: 200)
                    .accessibilityLabel("Big Shame Software")
                    .padding(.top, 4)

                VStack(spacing: 2) {
                    Text("N©! Big Shame Software 2026")
                    Text("a Big Shame Software app · public domain")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 24)
        }
        .frame(width: 360)
        .foregroundStyle(colorScheme == .dark ? BSSBrand.cream : BSSBrand.plumInk)
        .background(BSSBrand.surface(colorScheme, category: category))
    }
}

#Preview("Light") { AboutView().preferredColorScheme(.light) }
#Preview("Dark") { AboutView().preferredColorScheme(.dark) }
