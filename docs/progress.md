# Avancement — Release Exporter

_Dernière mise à jour : 2026-09-28_

## Fait
- Spec et plan : `docs/superpowers/specs/2026-09-25-ep-metadata-export-design.md`, `docs/superpowers/plans/2026-09-25-release-exporter.md`.
- Tâches 1 à 9 du plan implémentées (branche `feat/release-exporter`), 89 tests unitaires verts, luacheck propre.
- Relecture complète par un relecteur indépendant : 2 critiques et 6 importants corrigés, avec tests.
- Vérifications REAPER 7.80 (`docs/reaper-api-notes.md`) : GUID des régions, casse des clés ExtState, `RENDER_TARGETS`,
  identifiants de tags confirmés par exiftool sur de vrais rendus (MP3, WAV, FLAC), pochette MP3/WAV/FLAC.
- Interface restylée (thème quasi noir, accent vert, maquette C) ; « release » remplace « EP » dans les textes.
- Presets de rendu capturés et vérifiés par rendu : WAV 24/16 bits, MP3 CBR 320 kbps, FLAC 24 bits.
- Checklist manuelle (`docs/testing.md`) terminée sur REAPER 7.80 le 2026-09-28 : sans ReaImGui, aspect visuel,
  lot 1 (édition, pochette JPEG/PNG, synchro, persistance), export WAV 24 + MP3 vérifié à l'exiftool, annulation
  d'un rendu, long export, autre projet dans le même onglet, changement d'onglet. Les autres points sont couverts
  par les tests automatiques et le rendu de bout en bout. Fichier partiel laissé par un rendu annulé : non relevé.

## Reste à faire
1. **Publier** : dépôt GitHub, `reapack-index --commit` pour générer `index.xml`, CI verte.

## Points mineurs reportés (relecture)
- Les jobs et l'existence de la pochette sont recalculés à chaque image (à déplacer dans `rebuild`).
- La vérification de la pochette utilise un chemin brut dans l'app et un chemin nettoyé dans la validation.
- Les noms réservés Windows et les noms trop longs ne sont pas nettoyés.
- Les dossiers de sortie relatifs ou avec `~` ne sont pas refusés.
- Un dossier impossible à créer n'est détecté qu'à l'export.
- L'avertissement d'écrasement et la suppression ne s'appuient pas sur la même liste de chemins.
- Une région sans GUID est ignorée sans rien signaler.
- Les réglages de rendu restants (canaux, normalisation) ne sont pas affichés dans la confirmation.
- Un brouillon peut rester en mémoire si sa ligne disparaît.
