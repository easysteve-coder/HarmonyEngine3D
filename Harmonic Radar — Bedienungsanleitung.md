## Harmonic Radar — Bedienungsanleitung

---

### Öffnen und Schließen

**Taste `R`** öffnet und schließt das Radar-Panel. Das Panel erscheint oben rechts im Spielfenster und kann jederzeit während des Flugs ein- und ausgeblendet werden. Es hat keinen Einfluss auf das Spielverhalten — es ist ein reines Beobachtungswerkzeug.

---

### Was das Radar zeigt

Das Radar ist eine **Draufsicht** (Vogelperspektive) auf die XZ-Ebene der 3D-Welt. Die Y-Achse (Höhe) wird ignoriert — alle Objekte werden so dargestellt, als lägen sie auf derselben Ebene.

**Orientierung:**

- Der **Spieler** befindet sich immer in der Mitte
- Der **Pfeil ↑** zeigt in die Flugrichtung „vorwärts" (negative Z-Achse in SceneKit)
- Die drei konzentrischen Ringe markieren 33 %, 66 % und 100 % der maximalen Radarreichweite (350 Welt-Einheiten)

---

### Die Punkte im Radar

Jeder **farbige Punkt** ist ein Akkord-Node in der Welt. Der Punkt liegt da, wo der Akkord im 3D-Raum steht. Darunter steht der Akkordname.

| Farbe             | Bedeutung                                                                                                                         |
| ----------------- | --------------------------------------------------------------------------------------------------------------------------------- |
| **Grün**          | Dieser Node ist das aktive Magnet-Ziel der RuntimeHarmonik (`selectedNodeID`). Der Spieler wird subtil in seine Richtung gezogen. |
| **Gelb**          | Dieser Akkord ist die Empfehlung der HarmonyLogic (`suggestedChord`) — harmonisch passend zur aktuellen Situation.                |
| **Hellblau-weiß** | Dieser Akkord war der zuletzt aktivierte (`activeChord`) — du bist gerade dort durchgeflogen.                                     |
| **Grau**          | Alle übrigen Nodes im Sichtbereich — keine besondere harmonische Rolle gerade.                                                    |

Grüne und gelbe Nodes haben zusätzlich einen **Glow-Ring** (vergrößerter halbtransparenter Außenkreis), um sie auch bei dicht liegenden Nodes sofort erkennbar zu machen.

---

### Der Magnet-Marker (Magenta)

Wenn die RuntimeHarmonik ein aktives Magnet-Ziel hat, erscheint an dessen **Weltposition** ein **offener Magenta-Ring**. Dieser Ring zeigt nicht einfach denselben Wert wie der grüne Punkt — er zeigt die tatsächliche räumliche Position, auf die der Magnetismus zieht.

Im Normalfall liegen grüner Punkt und Magenta-Ring exakt übereinander. Sie können auseinanderfallen, wenn:

- der Node gerade neu geladen wurde und die Entscheidung noch nicht aktualisiert ist
- das Magnet-Ziel aus einer Entscheidung stammt, die kurz vor einem Reload gesetzt wurde

**Magenta-Ring = tatsächlicher Zielpunkt im Raum. Grüner Punkt = der Node, den die Harmonik empfiehlt.**

---

### Die Statuszeilen

Unterhalb des Radar-Canvas befinden sich fünf Informationszeilen:

#### `suggested` (gelb)

Die harmonische Empfehlung der HarmonyLogic — welcher Akkord als Nächstes gespielt werden sollte. Wird beim letzten `onChordActivated`-Event gesetzt und bleibt bis zum nächsten Akkordwechsel stehen.

#### `target` (grün)

Das konkrete Magnet-Ziel: Node-ID und aktuelle Distanz in Metern. Beispiel: `"G7 84m"` bedeutet, der Magnetismus zieht gerade auf den G7-Node, der 84 Meter entfernt ist.

Zeigt `–`, wenn kein Magnet-Ziel aktiv ist (z. B. Strategie `noCandidate`).

#### `active` (hellblau-weiß)

Der Name des Akkords, der zuletzt durch Annäherung ausgelöst wurde. Ändert sich bei jedem neuen Akkord-Trigger.

#### `magnet` (magenta)

**Live-Distanz** vom Spieler zum Magnet-Ziel in Metern — aktualisiert sich kontinuierlich (~10 Hz). Zeigt `–`, wenn kein Magnet-Ziel gesetzt ist. Dieser Wert ist unabhängig vom `target`-Eintrag: `target` kommt aus der letzten Entscheidung, `magnet` misst die aktuelle räumliche Entfernung in Echtzeit.

#### `strategy` (farbig je Strategie)

Die Entscheidungsstrategie der letzten RuntimeHarmonik-Auswertung:

| Wert                 | Farbe           | Bedeutung                                                                    |
| -------------------- | --------------- | ---------------------------------------------------------------------------- |
| `magnetismCandidate` | Grün            | Ein passender Folgeakkord wurde gefunden und als Ziel gesetzt                |
| `noCandidate`        | Gelb (gedämpft) | HarmonyLogic hat einen Vorschlag, aber kein passender Node ist in Reichweite |
| `noSuggestion`       | Grau            | Die GraphEngine hat keinen harmonisch sinnvollen Folgeakkord gefunden        |

---

### Aktualisierungsverhalten

Das Radar hat zwei getrennte Update-Pfade:

**Kontinuierlich (~10 Hz):** Nodes, Spielerposition und Magnet-Ziel werden jeden 6. Render-Frame live aktualisiert. Das Radar zeigt also immer den aktuellen räumlichen Zustand — unabhängig davon, ob du gerade einen Akkord auslöst oder nicht.

**Ereignisbasiert (bei Akkord-Aktivierung):** `suggested`, `target`, `active` und `strategy` werden nur beim Durchfliegen eines Akkords aktualisiert. Zwischen zwei Akkorden bleibt die letzte bekannte Entscheidung sichtbar. Das ist beabsichtigt — so kann man die Entscheidung nachvollziehen, ohne dass sie sofort wegspringt.

---

### Typisches Bild während des Flugs

Wenn du durch die JSON-Welt fliegst:

- Alle 8 Akkord-Nodes des Rings sind als graue Punkte sichtbar
- Sobald du einen Akkord auslöst, wechselt er zu hellblau-weiß (`active`)
- Die RuntimeHarmonik wählt einen Folgeakkord — er wird grün (`target`) und der Magenta-Ring erscheint auf seiner Position
- Ein anderer Akkord kann gleichzeitig gelb sein (`suggested`) — wenn HarmonyLogic eine andere Empfehlung hat als der Magnetismus
- In der `magnet`-Zeile siehst du live, wie die Distanz zum Ziel kleiner wird, während du darauf zufliegst

---

### Was das Radar nicht zeigt

- Bass-Portale und Melodie-Wolken (keine Chord-Nodes)
- Höhenunterschiede (Y-Achse)
- Den Autopilot-Pfad
- Interne Zustände von RuntimeHarmonik oder GraphEngine

Das Radar ist ausschließlich für die Beobachtung der räumlichen Harmonie-Situation gedacht — kein Einfluss auf das Spielverhalten.
