## DesignerKit — HarmonyWeb-Viewer User Guide

---

### 1. What is the HarmonyWeb Viewer?

DesignerKit has two modes. In its normal mode it loads `.txt` networks and displays them as an interactive graph — with edge editing, autopilot, and gamepad navigation. The HarmonyWeb Viewer is a second, separate mode. It loads structured JSON files (called HarmonyWebs) and renders their contents visually.

The key distinction: there is nothing to edit in the HarmonyWeb Viewer. This is not a tool for building — it is a tool for reading. You see which chords a network contains, how they are connected, what relationship types the edges carry, which edges belong to the active layer, and whether the network has any formal errors.

The Viewer is the analysis tool for the 3D engine. What you see here is the same data foundation that the player navigates in 3D space. If a transition in the 3D world happens unexpectedly often or rarely, this is where you find out why: a missing edge, a wrong weight, the wrong layer.

---

### 2. Loading a HarmonyWeb

In the DesignerKit toolbar, to the right of the network picker, there is a small button with a globe icon labelled "Web". Clicking it activates the HarmonyWeb Viewer mode.

Once the mode is active, a new dropdown replaces the network picker. It contains all HarmonyWebs known to the bundle — currently `harmony-web-c-diatonic`, `harmony-web-c-center`, and `reference-core`. Selecting a name from this dropdown triggers the load.

Internally, the following happens: the JSON file is read through the same loader the 3D engine uses. Nodes and edges are validated, then the chord nodes are set up as layout points and initially arranged in a circle. A force-directed layout then starts automatically, pushing nodes apart while taking edge weights into account. This takes a moment — while it runs, the canvas shows a loading indicator.

The result is a view that permits no changes to the data structure. Edges cannot be added, removed, or reweighted. Edit mode is always inactive in the HarmonyWeb Viewer.

To leave the HarmonyWeb Viewer and return to normal mode, click the "×" button to the right of the web picker. DesignerKit will reload the last-used `.txt` network.

---

### 3. Reading the Display

#### Nodes

Each circle represents a chord. The label shows the canonical ID of the chord — the exact name as defined in the HarmonyWeb: `Cmaj7`, `G7`, `Dm7`, and so on. This ID is the same identifier the 3D engine uses internally for recognition and context checks.

Clicking a node selects it. All other nodes dim, and only the edges connected to that node remain fully visible. Weight labels also appear on those edges (more on this in section 4). Clicking the same node again deselects it.

#### Edges — directed and undirected

Edges appear in two basic forms. A plain line without an arrowhead is an undirected edge: the transition works equally in both directions. An arrowhead at the end of an edge marks a directed edge: the transition runs from source to target, not the other way around.

In practice: a directed edge from G7 to Cmaj7 means the 3D engine can choose Cmaj7 as a destination from G7 — but not the reverse via this edge. An undirected edge between Cmaj7 and Am7 means the transition is valid in both directions.

The directionality in a HarmonyWeb is musically motivated: resolution movements have a clear direction (dominant → tonic), while relationship edges have no preferred direction. More on this in section 5.

---

### 4. Reading Weights

Every edge has a weight between 0 and 1. In the idle state the weight is not displayed as a number — but it does influence the visual thickness of the edge. Thicker edges have higher weights.

When a node is selected, numeric labels appear on all edges connected to that node, showing the exact weight value, such as `0.85` or `0.40`.

Weights are not absolute probabilities. The 3D engine evaluates them relative to each other: starting from a given chord, all outgoing edges are compared, and a higher weight means a higher likelihood that this particular transition will be chosen. Whether a weight of `0.40` is rare depends entirely on what other edges lead away from the same node.

The useful thing to look at is the ratio. If a node has five outgoing edges and one of them has three times the weight of the others, that edge will be taken noticeably more often. If all edges have similar weights, the network is open and unpredictable at that point.

When designing a HarmonyWeb, it is more useful to think of weights not as absolute strengths but as statements about relative frequency. A V-I edge with weight `0.9` does not mean "this transition is very powerful" — it means "this transition should happen much more often than the alternatives from the same starting point."

---

### 5. Music Theory: What the Colours Mean

The colour of an edge shows its primary relationship type. The system has six types. Each describes a different kind of harmonic relationship between two chords — a different logic for why these two chords can or should follow each other.

---

#### Gold — V-I (Dominant → Tonic)

The V-I movement is the strongest harmonic resolution in Western functional harmony. To understand why, you have to look at what happens in the individual notes.

The dominant seventh chord — in C major that is G7 — consists of four notes: G, B, D, F. Within it lie two tension-laden intervals: the tritone between B and F (an augmented fourth, the most unstable interval in the tonal system) and the seventh F itself, which exerts downward pressure. The leading tone B wants to move a semitone upward to C. The seventh F wants to move a semitone downward to E. Together, these two movements resolve the chord completely into the tonic: B → C, F → E, and G remains as the fifth of Cmaj7 or steps to G.

This tension and resolution is the central principle of functional harmony. It produces the sense of movement, arrival, and conclusion. That is why V-I is the strongest edge in the system — and why it gets the most prominent colour.

In the HarmonyWeb, V-I edges are always directed. Resolution has a direction: from tension toward release. The reverse does not carry this function — you can move harmonically from the tonic to the dominant, but that is a different movement with different logic, not the inversion of V-I.

---

#### Orange — ii-V (Subdominant → Dominant)

The ii-V movement is the preparation for the resolution. In C major, ii is the supertonic minor seventh chord: Dm7 (D, F, A, C). Moving from Dm7 to G7 is a descending fifth movement — the root drops a fifth (or rises a fourth). This movement is the most common harmonic pattern in jazz and in European art music alike.

Why is ii-V so effective? Dm7 shares two notes with F major (the subdominant in C): F and A. It thereby takes on the subdominant function — the feeling of "breaking away" before the cadence — without the static quality that F major can sometimes have. The step from Dm7 to G7 is a fifth movement that generates its own momentum before G7 resolves into Cmaj7.

Together, ii-V-I cadences form the structural backbone of a large portion of jazz harmony. In the HarmonyWeb they are modelled as two separate edges: an orange edge (ii → V) and a gold edge (V → I). In the Viewer you can trace these chains: wherever an orange edge leads into a gold edge, a complete cadence is present.

The ii-V edge is directed because the descending fifth motion is conceivable in both directions, but as a harmonic gesture it only functions in one: the supertonic chord prepares the dominant, not the reverse.

---

#### Teal — relMajMin (Relative Major/Minor)

Every major key has a natural relative minor that uses exactly the same notes. C major and A minor share all seven tones of the diatonic scale — the difference lies only in the starting point, the root around which the tones gravitate. Cmaj7 (C, E, G, B) and Am7 (A, C, E, G) share three of four notes; the fourth in each case is the root of the other.

This relationship makes movement between tonic and relative chord — in either direction — particularly smooth and natural. There is no harmonic tension to overcome, no leading-tone pull, no tritone. You glide between two chords that inhabit the same harmonic space.

In the HarmonyWeb, relMajMin edges are undirected because this relationship has no preferred direction. Cmaj7 → Am7 and Am7 → Cmaj7 are equally natural. This is a fundamental difference from V-I and ii-V, where the direction is musicologically fixed.

In practice, teal edges are harmonic resting zones. They can be taken in either direction without generating a strong pull. They work well as connectors when you want to move between two areas of the graph without triggering a strong cadence.

---

#### Blue-green — parallelMajMin (Modal Interchange)

Parallel major and parallel minor share the same root but have different pitch sets. C major and C minor both start on C, but C minor has three lowered scale degrees: E♭ instead of E, A♭ instead of A, B♭ instead of B.

Modal interchange is the technique of introducing chords from the parallel key into a composition without fully changing key. In C major a classic example is the descending mediant motion: Cmaj7 → B♭maj7, where B♭maj7 comes from C minor (VII in C minor). Other examples are the move to E♭maj7 (III in C minor) or A♭maj7 (VI in C minor).

These chords sound surprising in a C major context, but not foreign — because C is still present as a tonal centre, keeping the harmonic gravity anchored. The effect is often dark and rich: a brief immersion in a different tonal colour before returning.

In `harmony-web-c-diatonic`, the modal interchange edges are found exclusively in the `modal` layer. In the `functional` layer they are invisible — which is musically correct, because they have no place in purely functional harmonic thinking. Switching to the `modal` layer reveals them in blue-green, showing which paths lead into the harmonic parallel universe.

These edges are directed because modal interchange is typically understood as a gesture away from the home context — a short excursion into minor — and the return journey is not the same gesture in reverse, but a separate act of returning.

---

#### Blue-grey — commonTone (Common-Tone Connection)

Two chords share one or more common tones. That alone is sufficient logic for a transition, even when no strong functional relationship is present. Common-tone connections are the harmonically weakest edges in the system — they justify a transition but generate no pull.

In jazz and modal music, common-tone movement plays a larger role than in classical functional harmony, because there the harmonic flow is often organised not through cadences but through timbres and textures. One chord follows another because they are sonically close, not because one resolves the other.

In the Viewer, common-tone edges are recognisable by their quiet blue-grey colour and typically medium to low weights. They can be directed or undirected, depending on how the HarmonyWeb is designed. In `harmony-web-c-diatonic` most common-tone edges are directed — an editorial decision: a preferred direction was specified wherever the melodic movement or voice-leading context suggested one.

---

#### Purple — tritSubst (Tritone Substitution)

Tritone substitution is a jazz technique. It exploits the fact that two dominant seventh chords whose roots are a tritone apart contain the same tritone within their structure — just with the roles swapped. G7 contains B and F. D♭7 contains F and C♭ (= B). The tritone is identical; only the roles of leading tone and seventh are exchanged.

This means: D♭7 resolves to Cmaj7 just as G7 does. The root moves a semitone downward — producing a particularly smooth chromatic bass motion that sounds unexpected but convincing in a tonal context.

In the HarmonyWeb, a purple edge marks such a substitution path. Functionally it means: this transition works like a dominant resolution, but the chord itself is not the "normal" dominant of the target key — it is a substitute chord, legitimised by the shared tritone.

Tritone substitutions are rare and harmonically striking. In the Viewer you can check whether they are placed where this effect is actually wanted — and whether the weight matches the musical function. A tritSubst edge with a very high weight will pull the network strongly toward chromatic motion at that point.

---

### 6. Understanding Layers

A HarmonyWeb can have multiple layers. A layer is a perspective on the same network: it defines which edges are relevant in a particular harmonic context. Edges that belong to more than one layer appear in both perspectives.

#### The functional layer

The `functional` layer contains the edges of classical major-minor functional harmony: dominant movements (V-I), subdominant preparations (ii-V), common-tone movements within the diatonic field, and the relative major/minor relationships. Everything that can be explained in C major without borrowing tones from another key belongs in this layer.

The functional layer is the standard harmonic vocabulary. It describes which transitions are possible and plausible from a purely functional point of view.

#### The modal layer

The `modal` layer additionally contains the modal interchange edges — connections to chords borrowed from the parallel key. In `harmony-web-c-diatonic` these are the blue-green edges to B♭maj7 and E♭maj7 (both from C minor).

These edges do not exist in the functional layer because they cannot be justified there — B♭ and E♭ are not part of the C major scale. In the modal layer they are included because modal thinking loosens the concept of "correct" tones and welcomes chords from related modes.

The relMajMin edges (teal) appear in both layers — relative major/minor relationships are valid in both functional and modal thinking.

#### What this means in the Viewer

In the Viewer, the layer picker controls which edges are treated as primary. Non-active edges do not disappear — they are dimmed strongly. This allows you to keep both perspectives in view: which connections belong to the harmonic foundation, and which appear only in the extended modal context?

In the 3D engine, the RuntimeHarmonik actively selects between layers. When the system switches to a modal layer (which will be configurable in future versions), the available edges change. The Viewer lets you assess these consequences in advance: what do I lose if I stay in the functional layer? What becomes available when I activate the modal layer?

---

### 7. Understanding Validation

Immediately below the toolbar, a yellow bar appears when the loaded HarmonyWeb contains formal problems. The bar lists the issues found. If there are no problems, the bar remains invisible.

Three categories of problems are detected.

First, the Viewer checks the chord naming convention. Every node ID must follow a specific pattern: a capital letter as the root (C, D, E, F, G, A, B), optionally followed by `b` or `#` as an accidental, then a suffix such as `maj7`, `7`, `m7`, `m7b5`, `dim7`, `dim`, or `m`. Deviations — spaces, symbols like `♭` or `Δ`, or unrecognised suffixes — are reported as warnings. The reason is pragmatic: the 3D engine compares chord names as strings. If a name in the JSON file deviates from the expected form, the comparison fails and the affected node is treated as unknown by the runtime.

Second, the Viewer checks for duplicate node IDs. Every chord name may appear only once. Two nodes with the same ID would cause unpredictable behaviour in the graph.

Third, the Viewer validates edge references. Every edge names a source and a target. If either name is not present in the node list, the edge is technically invalid — it points to something that does not exist.

A warning does not mean a crash. The HarmonyWeb is still displayed. The warning is a pointer that helps you find errors — repairs are made directly in the JSON file, not in the Viewer.

---

### 8. Typical Workflow

A typical use case looks like this: you have created or modified a HarmonyWeb and want to verify that the structure is correct before setting it as the active world in the 3D engine.

Open DesignerKit, click "Web", select the HarmonyWeb from the dropdown. Once the force layout completes, the graph appears. First check whether the yellow validation bar appears — if it does, read the warnings and fix the problems in the JSON file.

Then look at the overall structure: are all expected chords present? Are there any isolated nodes — nodes without edges? Are the expected connections there?

Tap a central node — for instance `G7` in a diatonic web — and check which edges lead away from it. Does G7 have a gold edge to Cmaj7? Is there an orange edge from Dm7 to G7? Do the weights make sense: is the V-I edge actually heavier than the common-tone edges? Are the arrow directions correct?

Then switch the layer. What was visible in the functional layer? What appears additionally in the modal layer in blue-green? Are there edges that exist only in the modal layer — and does that make musical sense? Are the modal interchange chords meaningfully connected to the rest of the graph, or do they hang in isolation?

What you see here is the same foundation as what happens in 3D space. When the player flies past a particular chord node and the next suggestion from the RuntimeHarmonik seems unexpected, this is where you look: which edges lead away from that node, and what weights do they carry?

---

### 9. What the Viewer Cannot Do

The Viewer shows the structure of a HarmonyWeb — which chords and connections exist. It does not show how the runtime system interprets that structure.

The context mechanisms of HarmonyLogic — ii-V boost, return dampening, tension preservation — are not visible in the Viewer. These mechanisms modify effective weights at runtime based on the chord history of the last few steps. What looks equally weighted in the Viewer may occur with very different frequencies in actual use: a ii-V sequence in the run-up to an edge raises that edge's effective weight automatically, with no trace of this in the stored edge values.

Equally, the Viewer makes no statement about the spatial distribution of nodes in 3D space. The force layout is a pure display layout with no relation to the actual positions in the game world. Two nodes that appear close together in the Viewer may be far apart in the 3D world.

And, stated explicitly once more: there is no way to modify a HarmonyWeb through the Viewer. Anyone who wants to adjust edges, weights, or relation types does so directly in the JSON file.
