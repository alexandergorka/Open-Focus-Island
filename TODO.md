# Zurückgestellte Aufgaben

## Automatischer Apple-Fokus — ausdrücklich nicht im aktuellen Umfang

Erst bei einer späteren ausdrücklichen Beauftragung recherchieren oder implementieren. Gemeint ist die Steuerung von macOS-Fokussen wie „Nicht stören“, nicht der bestehende Pomodoro-Timer.

- [ ] Unterstützte Möglichkeiten zur Auswahl/Aktivierung/Deaktivierung eines Apple-Fokus prüfen.
- [ ] Vorher aktiven Fokus erkennen und nach der Sitzung wiederherstellen.
- [ ] Manuelle Änderungen während der Sitzung erkennen und respektieren; keinen inzwischen manuell gewählten Fokus überschreiben.
- [ ] Einmalige Einrichtung von Apple-Kurzbefehlen ist vom Nutzer akzeptiert. Prüfen, ob damit alle erforderlichen Funktionen zuverlässig möglich sind.
- [ ] Auswahl lokal und rückwärtskompatibel speichern.
- [ ] Verhalten bei Pausieren/Fortsetzen, Erholungspausen, Neustart und Absturz festlegen und testen.
- [ ] Fehler, Zeitüberschreitungen und verspätete Antworten behandeln, ohne den Timer zu blockieren.
- [ ] Tatsächliche macOS-Steuerung und Wiederherstellung nativ prüfen.

Keine Voraussetzung für Dragging, Fensterhöhe, Notch-Darstellung oder Sounds. Bis zur Wiederaufnahme keine Platzhalter-Implementierung, Kurzbefehle-Einrichtung oder zusätzliche Fokus-Berechtigungen.

## Gewählte Sounds — F1/B5, technische Umsetzung abgeschlossen

- [x] Ereignis-Policy und Kandidaten recherchiert und technisch geprüft (S1/S2).
- [x] Generator/Audio-Audit nach Header-Regression unabhängig freigegeben (S3a).
- [x] Player mit echten Bundle-Testdateien unabhängig freigegeben (S4a).
- [x] Nutzerwahl2026-10-09: F1 für Fokusende, B5 für Pausenende; Generatoranpassung ausschließlich am B5-Eintrag freigegeben (OptionA).
- [x] Gewählte finale Assets und Quellen-/Lizenzmanifest geliefert, unabhängig freigegeben und übernommen (S3b); echter Player-/Bundle-Decode 7/7 und QS freigegeben (S4b).
- [x] Sound-Einstellung, natürliche Live-Abschlüsse und Schutz vor doppelten/alten Geräuschen angeschlossen; unabhängige QS APPROVED (S5/S6), Gesamtsuite139/139, Releasebau erfolgreich.
- [x] Finale Sounds vor Signierung ins lokale App-Paket aufnehmen; Bundle-Audit, echte Decodierung und tatsächlichen Wiedergabestatus prüfen (S7), native Fokus-/Pausen-Abschlüsse in finaler QA-App fehlerfrei.
- [ ] Optionaler subjektiver Hörtest auf dem Zielgerät; Software bestätigt erfolgreiche Wiedergabe, beurteilt jedoch nicht das Hörerlebnis.

F1/B5 sind geliefert, bytegleich übernommen und im Controller integriert und stehen wie das restliche Projekt unter der MIT-Lizenz. S3b/S4b/S5/S6/S7 sind integriert und unabhängig freigegeben. Das finale lokale App-Paket ist gebaut und gestartet.
