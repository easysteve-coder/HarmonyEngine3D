// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "HarmonyEngine3D",
    defaultLocalization: "de",
    platforms: [.macOS(.v13)],
    targets: [

        // ── Gemeinsame Modelle + Netzwerk-Parser ──────────────────────────
        .target(
            name: "HarmonyShared",
            path: "Sources/HarmonyShared",
            resources: [
                .process("Resources")
            ]
        ),

        // ── 3D Flug-App ───────────────────────────────────────────────────
        // Haengt seit S-02b zusaetzlich von HarmonyAudioCore ab: der aktive
        // SynthNode-/VoicePool-Renderpfad rendert Stimmen ueber AudioCoreVoice
        // statt einer zweiten DSP-Kopie (siehe SynthNode.swift).
        .executableTarget(
            name: "HarmonyEngine3D",
            dependencies: ["HarmonyShared", "HarmonyAudioCore"],
            path: "Sources/HarmonyEngine3D",
            resources: [
                .process("Resources")   // minimal.sf2 → Bundle.module
            ],
            linkerSettings: [
                .linkedFramework("GameController")
            ]
        ),

        // ── Designer Kit (2D Navigator) ───────────────────────────────────
        .executableTarget(
            name: "DesignerKit",
            dependencies: ["HarmonyShared", "HarmonyAuthoring"],
            path: "Sources/DesignerKit",
            linkerSettings: [
                .linkedFramework("GameController"),
                .linkedFramework("CoreMIDI")
            ]
        ),

        // ── Authoring-Fundament (Construction Kit V1, M2) ──────────────────
        // Editierbarer HarmonyMapDocument-Draft mit Command-Stack/Undo-Redo,
        // Dokument-I/O (HarmonyMapDocumentStore) und Workspace-Sidecar
        // (HarmonyMapWorkspaceStore). Haengt nur von HarmonyShared ab.
        // DesignerKit haengt seit K-02 von HarmonyAuthoring ab; HarmonyEngine3D
        // (noch) nicht.
        .target(
            name: "HarmonyAuthoring",
            dependencies: ["HarmonyShared"],
            path: "Sources/HarmonyAuthoring"
        ),

        // ── Audio-DSP-Fundament (S-02a/S-02b, Audio-Track A) ────────────────
        // Reine, testbare DSP-Schicht ohne AVFAudio/SwiftUI/SceneKit/AppKit/
        // CoreMIDI/GameController- oder App-Code-Abhaengigkeit. Bildet die
        // Legacy-Voice-Semantik (Oszillatoren, ADSR, Biquad-Tiefpass,
        // Constant-Power-Pan) behavior-nah als Value-Modell + feste
        // Render-API ab. Seit S-02b von HarmonyEngine3D verdrahtet:
        // SynthNode.VoicePool rendert Stimmen ueber AudioCoreVoice.
        .target(
            name: "HarmonyAudioCore",
            path: "Sources/HarmonyAudioCore"
        ),

        // ── Tests: HarmonyShared (Codec, Graph, Determinismus) ─────────────
        .testTarget(
            name: "HarmonySharedTests",
            dependencies: ["HarmonyShared"],
            path: "Tests/HarmonySharedTests"
        ),

        // ── Tests: HarmonyEngine3D (NoteEventQueue — Transport/Overflow) ───
        // Haengt seit Runde 040 / V-01 zusaetzlich von HarmonyAuthoring ab —
        // nur fuer den Testtarget, um eine Kit-nahe HarmonyMap
        // (HarmonyMapDocumentStore/DiatonicHarmonyBuilder) fuer den
        // Vertikalslice-Nachweis "Kit-Map -> Importordner -> WorldSession"
        // zu erzeugen. Der Runtime-Produktcode (HarmonyEngine3D-Target
        // oben) bleibt Authoring-/DesignerKit-frei.
        // Haengt seit S-02b (Runde 047) zusaetzlich von HarmonyAudioCore ab —
        // fuer die expliziten Mapping-Tests (SynthParams/Waveform ->
        // AudioCoreSynthParameters/AudioCoreWaveform), die Core-Typnamen
        // direkt benennen.
        .testTarget(
            name: "HarmonyEngine3DTests",
            dependencies: ["HarmonyEngine3D", "HarmonyAuthoring", "HarmonyAudioCore"],
            path: "Tests/HarmonyEngine3DTests"
        ),

        // ── Tests: HarmonyAuthoring (Document/Command/Undo-Redo/Snapshot) ──
        .testTarget(
            name: "HarmonyAuthoringTests",
            dependencies: ["HarmonyAuthoring"],
            path: "Tests/HarmonyAuthoringTests",
            resources: [
                .process("Resources")
            ]
        ),

        // ── Tests: DesignerKit (Workspace-/Dokument-Adapterlogik, K-03) ────
        .testTarget(
            name: "DesignerKitTests",
            dependencies: ["DesignerKit"],
            path: "Tests/DesignerKitTests"
        ),

        // ── Tests: HarmonyAudioCore (Oszillatoren, ADSR, Filter, Pan, S-02a) ──
        .testTarget(
            name: "HarmonyAudioCoreTests",
            dependencies: ["HarmonyAudioCore"],
            path: "Tests/HarmonyAudioCoreTests"
        )
    ]
)
