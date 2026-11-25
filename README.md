# Vitals

Die Lebenszeichen deines Mac in der Menüleiste: Prozessor, Speicher, Laufwerke, Netzwerk und Akku in einem Fenster, jedes mit seiner Kurve auf einer gemeinsamen Zeitachse.

## Was das Fenster kann

- **Zustand in einem Satz.** Oben steht, wie es dem Mac geht („Entspannt“, „Unter Last“, „Speicher wird knapp“) und woran es liegt, z. B. welche App gerade am meisten belegt.
- **Zeitreise.** Mit dem Mauszeiger über eine Kurve fahren: Alle Werte im Fenster zeigen dann den Zustand von diesem Moment, samt der App, die damals am meisten gerechnet hat. Der Zeitraum lässt sich zwischen 10 Minuten und 1 Stunde umschalten.
- **Details auf Klick.** Ein Klick auf einen Bereich klappt ihn auf (Kerne, Speicheraufteilung, Apps, IP-Adresse, Akkuzustand); die anderen Bereiche rücken solange auf eine Zeile zusammen.
- **Apps statt Prozesse.** Hilfsprozesse zählen zu ihrer App, ein Browser mit 70 Prozessen ist eine Zeile.
- **Laufwerke.** Klick öffnet das Laufwerk im Finder, externe Laufwerke lassen sich direkt auswerfen.
- **Menüleiste.** Das Symbol ist ein Herzschlag, der mit der Prozessorlast stärker ausschlägt. Auf Wunsch steht ein Wert daneben (Prozessor, Speicher, Netzwerk oder Verbrauch).

## Bauen und starten

```sh
./build.sh            # build/Vitals.app
./build.sh install    # zusätzlich nach /Applications kopieren und starten
swift test            # Tests
```

Voraussetzung: macOS 14 oder neuer, Xcode-Kommandozeilenwerkzeuge. Keine fremden Abhängigkeiten.

Zum Ausprobieren ohne echte Daten:

```sh
build/Vitals.app/Contents/MacOS/Vitals --demo                      # erfundene Werte
build/Vitals.app/Contents/MacOS/Vitals --snapshot <Ordner> [main|processor|memory|network|power|scrub] [--real]
```

`--snapshot` rendert das Fenster hell und dunkel als PNG und beendet sich, gut zum Prüfen von Änderungen an der Oberfläche.

```sh
build/Vitals.app/Contents/MacOS/Vitals --soak 60 [--real]          # Dauerlauf, meldet alle 5 s den Speicher
```

`--soak` lässt das Fenster unsichtbar mit laufenden Werten arbeiten. Damit fällt auf, wenn eine Änderung an der Oberfläche Speicher verliert.

## Aufbau

- `Sources/VitalsCore`: alles ohne Oberfläche: Datenmodell (`Model.swift`), Messfühler (`Probes/`), Verlauf, Zustandsurteil, Formatierung, Taktgeber.
- `Sources/Vitals`: die App: Menüleisten-Symbol und Fenster (`MenuBarController.swift`), Zustand (`Monitor.swift`), Kurven (`Trace.swift`), Bereiche (`Rows.swift`, `Details.swift`).
- `Tests/VitalsCoreTests`: Tests für die Rechenlogik.

Gemessen wird alle 2 Sekunden auf einer eigenen Warteschlange. Die Prozessliste (`ps`) ist der einzige teure Teil und läuft bei geschlossenem Fenster nur alle 10 Sekunden.

## Rollende Ziffern

Die Ziffern rollen über eine eigene Ansicht (`RollingText`), nicht über `.contentTransition(.numericText())`. Die Systemanimation zeichnet jede Ziffer in jedem Bild etwas anders, und macOS behält all diese Zwischenbilder: Bei offenem Fenster wuchs die App um rund 1 MB pro Sekunde.

## Bekannte Grenzen

- Der Speicher von Systemprozessen anderer Benutzer (z. B. WindowServer) lässt sich ohne Sonderrechte nur ungefähr lesen und fällt zu klein aus.
- Die CPU-Temperatur kommt über eine nicht dokumentierte Schnittstelle; wo sie fehlt, wird der Wert einfach nicht angezeigt.
- Der Verlauf lebt nur im Arbeitsspeicher und beginnt nach jedem Start neu.
