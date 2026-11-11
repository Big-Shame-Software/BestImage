# Changelog

All notable changes to BestImage are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and BestImage uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.2.0] - 2026-11-11

### Added
- A Crop section, picked from the switch at the top of the window. Images dropped here are never scored or renamed.
- A crop window with Auto-Detect, zoom, and edge controls that read the pixel color along each edge.
- Cut out background: removes a white or transparent background and its drop shadow, with brushes to keep or remove areas by hand.
- Split into separate images: proposes one box per item on a sheet, such as several posters in one scan, and saves each box as its own image.
- Find Trims: suggests border trims at several fuzz levels using ImageMagick, when it is installed.

### Known issues
- Find Trims needs ImageMagick from Homebrew. Without it, the rest of the crop window still works.
- The app icon has no dark or tinted variants yet.

## [1.1.1] - 2026-11-11

The 1.1.0 About window said "Public domain" but skipped the N©! line our own styleguide asks for. We wrote the styleguide. This puts it right.

### Changed
- The About window and the app's Get Info copyright now show the Big Shame Software N©! line: "N©! Big Shame Software 2026. No rights reserved."

### Known issues
- The app icon has no dark or tinted variants yet.

## [1.1.0] - 2026-11-11

### Added
- An About window, under the BestImage menu, with the version, a short tagline and Big Shame Software attribution.
- Pixel art in the empty drop zone.

### Changed
- A new app icon: a pixel floppy disk on magenta, part of the Big Shame Software icon family.

## [1.0.0] - 2026-11-08

### Added
- First public release. Drop images to score them with Apple Vision's aesthetics score, rename them in place for sorting, and restore the original names.
