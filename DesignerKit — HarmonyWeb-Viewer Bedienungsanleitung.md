## DesignerKit — HarmonyWeb-Viewer Bedienungsanleitung

---

### 1. Was ist der HarmonyWeb-Viewer?

DesignerKit hat zwei Modi. Im normalen Modus lädt es `.txt`-Netzwerke und zeigt sie als interaktiven Graphen — mit Kanten editieren, Autopilot, Gamepad-Navigation. Der HarmonyWeb-Viewer ist ein zweiter, separater Modus. Er lädt strukturierte JSON-Dateien (sogenannte HarmonyWebs) und stellt deren Inhalt visuell dar.

Der wichtigste Unterschied: Im HarmonyWeb-Viewer gibt es nichts zu editieren. Das ist kein Werkzeug zum Bauen, sondern zum Lesen. Man sieht, welche Akkorde in einem Netzwerk vorhanden sind, wie sie verbunden sind, welche Beziehungstypen die Kanten haben, welche Kanten zum aktiven Layer gehören — und ob das Netzwerk formale Fehler enthält.

Der Viewer ist das Analysetool zur 3D-Engine. Was man hier sieht, ist dieselbe Datengrundlage, auf der der Spieler im 3D-Raum navigiert. Wenn ein Übergang im 3D-Raum unerwartet häufig oder selten passiert, kann man hier nachvollziehen warum: fehlende Kante, falsches Gewicht, falscher Layer.

---

### 2. Ein HarmonyWeb laden

In der Werkzeugleiste von DesignerKit befindet sich rechts neben dem Netzwerk-Picker ein kleiner Button mit einem Globus-Symbol und der Aufschrift „Web". Ein Klick darauf aktiviert den HarmonyWeb-Viewer-Modus.

Sobald der Modus aktiv ist, ersetzt ein neues Dropdown-Menü den bisherigen Netzwerk-Picker. Es enthält alle bekannten HarmonyWebs im Bundle — aktuell `harmony-web-c-diatonic`, `harmony-web-c-center` und `reference-core`. Die Auswahl eines Namens aus diesem Menü löst den Ladevorgang aus.

Intern passiert dabei Folgendes: Die JSON-Datei wird über denselben Loader gelesen, den auch die 3D-Engine verwendet. Nodes und Kanten werden überprüft, dann werden die Akkordknoten als Layout-Punkte aufgebaut und initial im Kreis angeordnet. Anschließend startet automatisch ein Force-Layout, das die Knoten auseinanderschiebt und dabei die Kantengewichte berücksichtigt. Dieser Prozess dauert einen Moment — während er läuft, zeigt das Canvas einen Ladeindikator.

Das Ergebnis ist eine Ansicht, die keine Benutzereingriffe in die Datenstruktur erlaubt. Kanten können weder hinzugefügt noch entfernt noch gewichtet werden. Der Edit-Modus ist im HarmonyWeb-Viewer grundsätzlich inaktiv.

Um den HarmonyWeb-Viewer zu verlassen und zum normalen Modus zurückzukehren, genügt ein Klick auf das „×"-Symbol rechts neben dem Web-Picker. DesignerKit lädt dann das zuletzt verwendete `.txt`-Netzwerk neu.

---

### 3. Die Darstellung lesen

#### Knoten

Jeder Kreis repräsentiert einen Akkord. Die Beschriftung zeigt die kanonische ID des Akkords, also den exakten Namen wie er im HarmonyWeb definiert ist: `Cmaj7`, `G7`, `Dm7` und so weiter. Diese ID ist dieselbe, die die 3D-Engine intern zur Identifikation und Kontextprüfung verwendet.

Klickt man auf einen Knoten, wird er ausgewählt. Alle anderen Knoten dimmen ab, und nur die Kanten dieses Knotens bleiben vollständig sichtbar. Zusätzlich erscheinen Gewichtslabels an den Kanten (dazu mehr in Abschnitt 4). Ein erneuter Klick auf denselben Knoten hebt die Auswahl auf.

#### Kanten — gerichtet und ungerichtet

Kanten erscheinen in zwei Grundformen. Eine einfache Linie ohne Pfeil ist eine ungerichtete Kante: der Übergang funktioniert in beide Richtungen gleich. Ein Pfeil am Ende einer Kante markiert eine gerichtete Kante: der Übergang verläuft von der Quelle zum Ziel, nicht umgekehrt.

In der Praxis bedeutet das: eine gerichtete Kante von G7 nach Cmaj7 bedeutet, dass die 3D-Engine von G7 aus Cmaj7 als mögliches Ziel wählen kann — aber nicht umgekehrt über diese Kante. Eine ungerichtete Kante zwischen Cmaj7 und Am7 bedeutet, dass der Übergang in beide Richtungen gilt.

Die Richtungsentscheidung im HarmonyWeb ist musiktheoretisch motiviert: Auflösungsbewegungen haben eine klare Richtung (dominantisch → tonisch), während Verwandtschaftsbeziehungen keine bevorzugte Richtung kennen. Mehr dazu in Abschnitt 5.

---

### 4. Gewichte lesen

Jede Kante hat ein Gewicht zwischen 0 und 1. Das Gewicht ist im Ruhezustand nicht eingeblendet — es beeinflusst aber die visuelle Dicke der Kante. Dickere Kanten haben höhere Gewichte.

Sobald ein Knoten ausgewählt ist, erscheinen an allen Kanten dieses Knotens numerische Labels mit dem genauen Gewichtswert, zum Beispiel `0.85` oder `0.40`.

Gewichte sind keine absoluten Wahrscheinlichkeiten. Die 3D-Engine wertet sie relativ zueinander aus: von einem gegebenen Akkord aus werden alle ausgehenden Kanten verglichen, und ein höheres Gewicht bedeutet eine höhere Wahrscheinlichkeit, dass dieser Übergang gewählt wird. Ob ein Gewicht von `0.40` selten ist, hängt davon ab, welche anderen Kanten von demselben Knoten wegführen.

Sinnvoll ist der Blick auf das Verhältnis: wenn ein Knoten fünf ausgehende Kanten hat und eine davon das dreifache Gewicht der anderen, wird diese Kante deutlich häufiger genommen. Wenn alle Kanten ähnliche Gewichte haben, ist das Netzwerk an dieser Stelle offen und unvorhersehbar.

Beim Gestalten eines HarmonyWebs lohnt es sich, die Gewichte nicht als absolute Stärke zu denken, sondern als Aussage über relative Häufigkeit. Ein V-I-Übergang mit Gewicht `0.9` bedeutet nicht „dieser Übergang ist sehr stark", sondern „dieser Übergang soll deutlich häufiger passieren als die Alternativen von demselben Startpunkt".

---

### 5. Harmonielehre: Was die Farben bedeuten

Die Farbe einer Kante zeigt den primären Beziehungstyp. Das System kennt sechs Typen. Jeder Typ beschreibt eine andere Art von harmonischer Beziehung zwischen zwei Akkorden — eine andere Logik, warum diese beiden aufeinander folgen können oder sollen.

---

#### Gold — V-I (Dominante → Tonika)

Die V-I-Bewegung ist die stärkste harmonische Auflösung, die die westliche Funktionsharmonik kennt. Um zu verstehen, warum, muss man sich anschauen, was in den Tönen passiert.

Der Dominantseptakkord — in C-Dur ist das G7 — besteht aus vier Tönen: G, H, D, F. Darin liegen zwei spannungsreiche Intervalle: der Tritonus zwischen H und F (eine übermäßige Quarte, das instabilste Intervall im tonalen System) und die Septime F selbst, die nach unten drückt. Der Leitton H will einen Halbtonschritt aufwärts nach C. Die Septime F will einen Halbtonschritt abwärts nach E. Beide Bewegungen zusammen lösen den Akkord vollständig in die Tonika auf: H → C, F → E, und G bleibt als Quinte von Cmaj7 bestehen oder geht nach G.

Diese Spannung und Auflösung ist das zentrale Prinzip der Funktionsharmonik. Sie erzeugt das Gefühl von Bewegung, Ankunft, Schluss. Deshalb ist V-I die stärkste Kante im System — und deshalb bekommt sie die auffälligste Farbe.

Im HarmonyWeb sind V-I-Kanten immer gerichtet. Die Auflösung hat eine Richtung: von der Spannung zur Entspannung. Rückwärts gibt es diese Funktion nicht — man kann harmonisch von der Tonika zur Dominante gehen, aber das ist dann eine andere Bewegung mit anderer Logik, nicht die Umkehrung von V-I.

---

#### Orange — ii-V (Subdominante → Dominante)

Die ii-V-Bewegung ist die Vorbereitung der Auflösung. In C-Dur ist ii die Supertonikaparallele: Dm7 (D, F, A, C). Von Dm7 nach G7 ist eine Quintfallbewegung — die Wurzel fällt eine Quinte (oder steigt eine Quarte). Diese Bewegung ist das häufigste harmonische Muster im Jazz und in der europäischen Kunstmusik gleichermaßen.

Warum ist ii-V so wirkungsvoll? Dm7 teilt zwei Töne mit F-Dur (der Subdominante in C): F und A. Es übernimmt damit die subdominantische Funktion — das Gefühl des „Aufbrechens" vor der Kadenz — ohne die Stagnation, die F-Dur manchmal haben kann. Der Schritt von Dm7 zu G7 ist dann eine Quintbewegung, die ein eigenes Momentum erzeugt, bevor G7 in Cmaj7 auflöst.

Im Verbund bilden ii-V-I-Kadenzen die Grundstruktur eines Großteils der Jazz-Harmonik. Im HarmonyWeb sind sie als zwei separate Kanten modelliert: eine orange Kante (ii → V) und eine goldene Kante (V → I). Im Viewer kann man diese Ketten verfolgen: wo immer eine orangene Kante auf eine goldene folgt, liegt eine vollständige Kadenz vor.

Die ii-V-Kante ist gerichtet, weil die Quintfallbewegung zwar in beide Richtungen denkbar ist, aber als harmonische Geste nur in eine Richtung wirkt: die Supertonikaparallele bereitet die Dominante vor, nicht umgekehrt.

---

#### Teal — relMajMin (Dur-Moll-Verwandtschaft)

Jede Durtonart hat eine natürliche Mollverwandte, die genau dieselben Töne verwendet. C-Dur und a-Moll teilen alle sieben Töne der Durskala — der Unterschied liegt nur im Startpunkt, im Grundton, um den herum die Töne gravitieren. Cmaj7 (C, E, G, H) und Am7 (A, C, E, G) teilen drei von vier Tönen, der vierte ist der Grundton des jeweils anderen.

Diese Verwandtschaft macht Bewegungen zwischen Tonika und Tonikagegenklang (oder Tonikaparallele) besonders weich und natürlich. Es gibt keine harmonische Spannung zu überwinden, keine Leittonbewegung, kein Tritonus — man gleitet zwischen zwei Akkorden, die denselben harmonischen Raum bewohnen.

Im HarmonyWeb sind relMajMin-Kanten ungerichtet, weil diese Beziehung keine bevorzugte Richtung kennt. Cmaj7 → Am7 und Am7 → Cmaj7 sind beide gleich natürlich. Das ist ein fundamentaler Unterschied zu V-I und ii-V, wo die Richtung musiktheoretisch fest definiert ist.

Praktisch bedeutet das: teal-farbene Kanten sind harmonische Entspannungszonen. Man kann sie in beide Richtungen nehmen, ohne dass ein starker harmonischer Zug entsteht. Sie eignen sich gut als Verbindungen, wenn man zwischen zwei Bereichen des Graphen wechseln möchte, ohne eine starke Kadenz zu erzeugen.

---

#### Grünblau — parallelMajMin (Modal Interchange)

Parallel-Dur und Parallel-Moll teilen denselben Grundton, aber unterschiedliche Tonvorräte. C-Dur und c-Moll beginnen beide auf C, aber c-Moll hat drei erniedrigte Stufen: Eb statt E, Ab statt A, Bb statt B.

Modal Interchange bezeichnet die Technik, Akkorde aus der Paralleltonart in eine Komposition einzuführen, ohne die Tonart vollständig zu wechseln. In C-Dur ist ein klassisches Beispiel die Abwärtsmediantbewegung: Cmaj7 → Bbmaj7, wobei Bbmaj7 aus c-Moll stammt (VII in c-Moll). Ein anderes Beispiel ist der Wechsel zu Ebmaj7 (III in c-Moll) oder zu Abmaj7 (VI in c-Moll).

Diese Akkorde klingen in einem C-Dur-Kontext überraschend, aber nicht fremdartig — weil der Grundton C noch präsent ist und das harmonische Zentrum verankert bleibt. Der Effekt ist oft dunkel, satt, ein kurzes Eintauchen in eine andere Klangfarbe, bevor man zurückkommt.

Im HarmonyWeb `harmony-web-c-diatonic` sind die Modal-Interchange-Kanten ausschließlich im `modal`-Layer zu finden. Im `functional`-Layer sind sie unsichtbar — was musikalisch sinnvoll ist, denn in einer rein funktionalen Harmonisierung haben sie keinen Platz. Wechselt man in den `modal`-Layer, erscheinen sie in Grünblau und zeigen, welche Wege ins harmonische Paralleluniversum führen.

Die Kanten sind gerichtet, weil Modal Interchange typischerweise als Geste aus dem Grundkontext heraus verstanden wird — ein kurzer Ausflug nach Moll — und der Rückweg dann nicht dieselbe Geste ist, sondern eine Rückkehr.

---

#### Blaugrau — commonTone (Gemeintonbeziehung)

Zwei Akkorde teilen einen oder mehrere gemeinsame Töne. Das allein reicht als Übergangslogik, auch wenn keine starke funktionale Beziehung vorliegt. Gemeintonverbindungen sind die harmonisch schwächsten Kanten im System — sie rechtfertigen einen Übergang, erzeugen aber keinen Zug.

Im Jazz und in der modalen Musik spielen Gemeintonbewegungen eine größere Rolle als in der klassischen Funktionsharmonik, weil dort der harmonische Fluss oft nicht über Kadenzen, sondern über Klangfarben und Texturen organisiert wird. Ein Akkord folgt dem anderen, weil sie sich klanglich nahestehen, nicht weil einer den anderen auflöst.

Im Viewer erkennt man Gemeintonkanten an ihrer ruhigen, blaugrauen Farbe und typischerweise mittleren bis niedrigen Gewichten. Sie sind gerichtet oder ungerichtet, je nachdem wie das HarmonyWeb gestaltet ist. Im `harmony-web-c-diatonic` sind die meisten Gemeintonkanten gerichtet — was eine editorische Entscheidung ist: die bevorzugte Richtung wurde dort festgelegt, wo die Melodiebewegung oder der Stimmführungskontext eine hat.

---

#### Violett — tritSubst (Tritonussubstitution)

Die Tritonussubstitution ist eine Technik aus dem Jazz. Sie nutzt die Tatsache, dass zwei Dominantseptakkorde, deren Grundtöne im Abstand eines Tritonus liegen, denselben Tritonus in ihrer Struktur enthalten — nur in umgekehrter Lage. G7 enthält H und F. Db7 enthält F und Cb (= H). Der Tritonus ist identisch, nur die Rollen von Leitton und Septime sind vertauscht.

Das bedeutet: Db7 löst nach Cmaj7 auf, genau wie G7. Der Grundton geht dabei einen Halbtonschritt abwärts — was eine besonders weiche, chromatische Bassbewegung ergibt, die in Dur-Moll-funktionalem Kontext fremdartig, aber überzeugend klingt.

Im HarmonyWeb markiert eine violette Kante einen solchen Substitutionsweg. Inhaltlich bedeutet sie: hier funktioniert dieser Übergang wie eine Dominantauflösung, aber der Akkord selbst ist kein „normaler" Dominantakkord der betreffenden Tonart — er ist ein Ersatz, der über den gemeinsamen Tritonus legitimiert ist.

Tritonussubstitutionen sind selten und klanglich auffällig. Im Viewer kann man prüfen, ob sie dort platziert sind, wo dieser Effekt gewünscht ist — und ob das Gewicht zur musikalischen Funktion passt. Ein tritSubst mit sehr hohem Gewicht wird das Netzwerk an dieser Stelle stark in Richtung chromatischer Bewegung ziehen.

---

### 6. Layer verstehen

Ein HarmonyWeb kann mehrere Layer haben. Ein Layer ist eine Perspektive auf dasselbe Netzwerk: er definiert, welche Kanten in einem bestimmten harmonischen Kontext relevant sind. Kanten, die zu mehreren Layern gehören, erscheinen in beiden Perspektiven.

#### Der functional-Layer

Der `functional`-Layer enthält die Kanten der klassischen Dur-Moll-Funktionsharmonik: Dominantbewegungen (V-I), Subdominantvorbereitungen (ii-V), Gemeintonbewegungen innerhalb des diatonischen Feldes und die Verwandtschaftsbeziehungen zwischen Dur- und Mollparallelen. Alles, was in C-Dur ohne Ton-Ausleihen aus anderen Tonarten erklärt werden kann, gehört in diesen Layer.

Der functional-Layer ist das harmonische Standardrepertoire. Er beschreibt, welche Übergänge aus rein funktionalem Denken heraus möglich und plausibel sind.

#### Der modal-Layer

Der `modal`-Layer enthält zusätzlich die Modal-Interchange-Kanten — also Verbindungen zu Akkorden, die aus der Paralleltonart stammen. Im `harmony-web-c-diatonic` sind das die grünblauen Kanten zu Bbmaj7 und Ebmaj7 (aus c-Moll).

Diese Kanten existieren nicht im functional-Layer, weil sie dort harmonisch nicht begründbar sind — Bb und Eb gehören nicht zur C-Dur-Skala. Im modal-Layer treten sie hinzu, weil die modale Denkweise den Begriff der „richtigen" Töne lockert und Akkorde aus verwandten Modi willkommen heißt.

Die relMajMin-Kanten (Teal) erscheinen in beiden Layern — Dur-Moll-Verwandtschaft ist sowohl im funktionalen als auch im modalen Denken gültig.

#### Was das für den Viewer bedeutet

Im Viewer steuert der Layer-Picker, welche Kanten als primär betrachtet werden. Die nicht-aktiven Kanten verschwinden nicht — sie werden stark gedimmt. Das erlaubt es, beide Perspektiven im Blick zu behalten: welche Verbindungen gehören zur harmonischen Grundstruktur, und welche kommen nur im erweiterten modalen Kontext hinzu?

In der 3D-Engine wählt die RuntimeHarmonik aktiv zwischen Layern. Wenn das System auf einen modalen Layer umschaltet (was in zukünftigen Versionen konfigurierbar sein wird), ändern sich die verfügbaren Kanten. Im Viewer kann man diese Konsequenzen vorab beurteilen: was verliere ich, wenn ich im functional-Layer bleibe? Was kommt hinzu, wenn ich den modal-Layer aktiviere?

---

### 7. Validierung verstehen

Direkt unterhalb der Toolbar erscheint eine gelbe Leiste, wenn das geladene HarmonyWeb formale Probleme enthält. Die Leiste listet die gefundenen Probleme auf. Gibt es keine Probleme, bleibt die Leiste unsichtbar.

Drei Arten von Problemen werden erkannt.

Erstens prüft der Viewer die Akkord-Namenskonvention. Jede Node-ID muss einem bestimmten Schema folgen: Großbuchstabe als Grundton (C, D, E, F, G, A, B), optional ein `b` oder `#` als Vorzeichen, dann ein Suffix wie `maj7`, `7`, `m7`, `m7b5`, `dim7`, `dim` oder `m`. Abweichungen — etwa Leerzeichen, Sonderzeichen wie `♭` oder `Δ`, oder unbekannte Suffixe — werden als Warnung gemeldet. Der Hintergrund ist pragmatisch: die 3D-Engine vergleicht Akkordnamen als Strings. Weicht ein Name in der JSON-Datei von der erwarteten Form ab, findet der Vergleich nicht statt, und die betroffene Node wird im Laufzeitsystem als unbekannt behandelt.

Zweitens prüft der Viewer auf doppelte Node-IDs. Jeder Akkordname darf nur einmal vorkommen. Zwei Nodes mit derselben ID würden im Graphen zu unvorhersehbarem Verhalten führen.

Drittens prüft der Viewer Kantenreferenzen. Jede Kante nennt eine Quelle und ein Ziel. Wenn einer dieser Namen nicht in der Node-Liste vorhanden ist, ist die Kante technisch ungültig — sie zeigt auf etwas, das nicht existiert.

Eine Warnung bedeutet kein Absturz. Das HarmonyWeb wird trotzdem angezeigt. Die Warnung ist ein Hinweis, der beim Finden von Fehlern hilft — repariert wird direkt in der JSON-Datei, nicht im Viewer.

---

### 8. Typischer Arbeitsablauf

Ein typischer Einsatz sieht so aus: Man hat ein HarmonyWeb erstellt oder angepasst und möchte prüfen, ob die Struktur stimmt, bevor man es als aktive Testwelt in der 3D-Engine einsetzt.

Man öffnet DesignerKit, klickt auf „Web", wählt das HarmonyWeb aus dem Dropdown. Nach dem Force-Layout erscheint der Graph. Als erstes prüft man, ob die gelbe Validierungsleiste erscheint — wenn ja, liest man die Warnungen und behebt die Probleme in der JSON-Datei.

Dann schaut man auf die Gesamtstruktur: Sind alle erwarteten Akkorde vorhanden? Gibt es Knoten, die isoliert dastehen — also ohne Kanten? Sind die erwarteten Verbindungen da?

Man tippt auf einen zentralen Knoten — etwa `G7` in einem diatonischen Web — und prüft, welche Kanten davon weggehen. Hat G7 eine goldene Kante nach Cmaj7? Gibt es eine orangene Kante von Dm7 nach G7? Stimmen die Gewichte: ist die V-I-Kante tatsächlich schwerer als die Gemeintonkanten? Ist die Pfeilrichtung korrekt?

Dann wechselt man den Layer. Was war im functional-Layer sichtbar? Was erscheint zusätzlich im modal-Layer in Grünblau? Gibt es Kanten, die nur im modalen Layer vorhanden sind — und macht das musikalisch Sinn? Sind die Modal-Interchange-Akkorde sinnvoll mit dem Rest verbunden, oder hängen sie isoliert?

Was man hier sieht, ist dieselbe Grundlage wie das, was im 3D-Raum passiert. Wenn der Spieler an einem bestimmten Akkord-Knoten vorbeifliegt und der nächste Vorschlag der RuntimeHarmonik überraschend wirkt, kann man im Viewer nachvollziehen, welche Kanten von dort wegführen und welche Gewichte sie haben.

---

### 9. Was der Viewer nicht kann

Der Viewer zeigt die Struktur eines HarmonyWebs — also welche Akkorde und Verbindungen vorhanden sind. Er zeigt nicht, wie das Laufzeitsystem diese Struktur interpretiert.

Die Kontextmechanismen der HarmonyLogic — ii-V-Boost, Rückkehrdämpfung, Spannungserhalt — sind im Viewer nicht sichtbar. Diese Mechanismen verändern zur Laufzeit die effektiven Gewichte abhängig vom Akkordverlauf der letzten Schritte. Was im Viewer als gleichwertig aussieht, kann im tatsächlichen Betrieb unterschiedlich häufig auftreten: eine ii-V-Sequenz im Vorfeld einer Kante erhöht deren effektives Gewicht automatisch, ohne dass das in den gespeicherten Kantenwerten steht.

Ebenso gibt es keine Aussage über die räumliche Verteilung der Knoten im 3D-Raum. Das Force-Layout des Viewers ist ein reines Darstellungslayout ohne Bezug zu den tatsächlichen Positionen in der Spielwelt. Zwei Knoten, die im Viewer nah beieinander liegen, können in der 3D-Welt weit voneinander entfernt sein.

Und, noch einmal explizit: Es gibt keine Möglichkeit, das HarmonyWeb über den Viewer zu verändern. Wer Kanten, Gewichte oder RelationTypes anpassen möchte, tut das direkt in der JSON-Datei.
