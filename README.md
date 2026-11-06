# KSlides

A native macOS lesson studio with editable slides, teacher notes, classroom presentation, PowerPoint/PDF/PNG export and a local MCP bridge. An optional Blender worker produces bounded geometry scenes from structured parameters. Original source is MIT licensed; sample illustrations are AI-generated and documented in [ARTWORK](Resources/ARTWORK.md).

This first community snapshot is version0.4.0. It is development source, not a notarized installer or a complete accessibility certification.

## Build and run

macOS15+, Swift6 and compatible Apple developer tools are required. No Swift package dependencies are downloaded by this package.

```sh
swift run KSlidesChecks
/bin/zsh scripts/build.sh
open dist/KSlides.app
```

The build creates an ad-hoc signed app. Copy it to your chosen Applications folder if desired. The community bundle identity is io.github.ilanvkn.kslides, separate from the original local prototype. Your lesson library lives in this app's private Application Support container; it is not included in this repository. Back it up before upgrades. A second app instance is refused while another copy holds the library lock. The original local app is not automatically migrated.

Create a lesson, add/edit slides, keep answers in teacher notes, and use Teach to inspect the student-facing sequence. Save/review edits before presenting. Export from the app into its managed Exports directory. No AI subscription or image service is bundled; your agent supplies any generated artwork you explicitly request.

## Connect an agent

Keep the app open. Configure a stdio MCP server with command `/absolute/KSlides.app/Contents/MacOS/KSlidesMCP`. For Codex:

```sh
codex mcp add kslides-community -- /absolute/KSlides.app/Contents/MacOS/KSlidesMCP
```

Use one KSlides registration deliberately if a local prototype is already connected. Start with tools/list and kslides_status, then read the lesson revision before editing. Example: “Create an original lesson about cube volume. Preview three slides first, keep teacher answers separate, then export an editable PowerPoint.”

The app listens on loopback with a per-launch bearer token saved in a mode0600 connection descriptor. The bridge reads that descriptor locally; do not upload it or expose the listener publicly. It can read/write lessons and exports and may return their contents to the connected AI host. Read-only discovery is not a privacy guarantee. KSLIDES_CONNECTION_FILE can select an explicitly chosen alternate descriptor.

For geometry rendering, install Blender separately at /Applications/Blender.app. Its bundled Python must provide NumPy. The worker accepts the supported scene JSON rather than arbitrary Python code; render tasks run locally and retain owned output/log files. A successful numerical check does not establish every rendering, teaching or accessibility requirement.

## Verification and contributions

The isolated community copy passed ten domain/geometry/tool-contract/ZIP checks and a release app build on the maintainer Mac. CI repeats those checks and builds the app on macOS. The test executable uses its own assertions; this is not an XCTest UI suite. Live UI, assistive technology, export fidelity and optional Blender integration still require independent reproduction on this exact public copy.

Open Issues for reproducible bugs and pull requests for focused changes. Describe expected behavior, platform/tool versions and synthetic reproduction steps. Do not include saved lesson libraries, learner information, local tokens, generated private artwork or raw connection files. Preserve source/license notices. No automatic updater, analytics or hosted model is included.
