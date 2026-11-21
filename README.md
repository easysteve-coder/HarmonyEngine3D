# HarmonyEngine3D

A musical instrument for macOS that you play by flying. You steer through a
three-dimensional space of chords (a *HarmonyWeb*); coming close to a chord,
a bass portal or a melody cloud makes it sound, with voice leading between
chords. It plays its own synthesizer or sends MIDI. A companion 2D editor,
*DesignerKit*, builds the harmonic worlds.

*Deutsch: Ein Instrument für macOS, das man durch Fliegen spielt. Man steuert
durch einen dreidimensionalen Akkordraum (HarmonyWeb); die Annäherung an
Akkorde, Bassportale und Melodiewolken lässt sie klingen, mit Stimmführung
zwischen den Akkorden. Klang aus dem eigenen Synthesizer oder per MIDI. Der
2D-Editor DesignerKit baut die harmonischen Welten.*

> **Status:** work in progress. The direction for the next versions (a
> non-linear "DAW in space" with samples, loops, tempo, live quantisation,
> Audio Unit hosting and a construction kit for sound worlds) is described in
> [`ROADMAP.md`](ROADMAP.md), section *Produktrichtung Rev. 8*.

## Features

- **Flight as performance:** keyboard and mouse, or a PS5 DualSense
  controller (sticks, triggers, gyro as MIDI CC).
- **Four musical channels:** chords (CH1), bass (CH2), melody (CH3) and chord
  tones from the controller (CH4), each with its own trigger distance.
- **Harmonic worlds:** curated HarmonyWeb maps (JSON, versioned schema with
  validator) and procedurally generated networks. Generation is deterministic:
  the same seed always builds the same world.
- **Harmonic magnet:** the graph of chord relations gently pulls the flight
  towards musically related chords.
- **Internal synthesizer** (atmospheric voice, deep-space reverb, per-channel
  effects) or **MIDI output** to a DAW or hardware; **MIDI input** with CC
  mapping onto four sound macros.
- **DesignerKit:** a 2D editor to create, edit, validate and save HarmonyWeb
  maps with undo/redo; the 3D app loads the same files.

## Build and run

Requirements: macOS 13 or later, Swift 5.10 toolchain (Xcode 15.3 or newer).
The project is a plain Swift package; Xcode can open `Package.swift` directly.

```sh
swift build
swift test
swift run HarmonyEngine3D    # the 3D instrument
swift run DesignerKit        # the 2D construction kit
```

## Documentation

- [`ARCHITECTURE.md`](ARCHITECTURE.md): modules, data flow, thread boundaries.
- [`ROADMAP.md`](ROADMAP.md): order of work and contracts.
- [`HarmonyNetwork_Spec_v1.md`](HarmonyNetwork_Spec_v1.md): map format.
- [`SYNTH_ARCHITECTURE_PLAN.md`](SYNTH_ARCHITECTURE_PLAN.md): synthesizer design.
- User guides (DesignerKit, Harmonic Radar) in the repository root.
- [`CHANGELOG.md`](CHANGELOG.md).

Most internal documents and code comments are in German.

## Sister projects

- [FIRSTofFIFTH](https://github.com/easysteve-coder/FIRSTofFIFTH): polyphonic,
  polyrhythmic MIDI step sequencer with Audio Unit hosting.
- [Planarium](https://github.com/easysteve-coder/Planarium): spatial instrument
  played with a laser scanner.

## Licence

HarmonyEngine3D is licensed under the GNU General Public License v3, see
[`LICENSE`](LICENSE). Third-party material: [`THIRD-PARTY-NOTICES.md`](THIRD-PARTY-NOTICES.md).
