# Avancement — Release Exporter

_Dernière mise à jour : 2026-09-27_

## Fait
- Spec et plan : `docs/superpowers/specs/2026-09-25-ep-metadata-export-design.md`, `docs/superpowers/plans/2026-09-25-release-exporter.md`.
- Tâches 1 à 9 du plan implémentées (branche `feat/release-exporter`), 73 tests unitaires verts, luacheck propre.
- Relecture complète par un relecteur indépendant : 2 critiques et 6 importants corrigés, avec tests.
- Vérifications REAPER 7.80 (`docs/reaper-api-notes.md`) : GUID des régions, casse des clés ExtState, `RENDER_TARGETS`,
  identifiants de tags confirmés par exiftool sur de vrais rendus (MP3, WAV, FLAC), pochette MP3/WAV/FLAC.
- Presets de rendu capturés et vérifiés par rendu : WAV 24/16 bits, MP3 CBR 320 kbps, FLAC 24 bits.

## Reste à faire
1. **Dérouler la checklist manuelle** `docs/testing.md` dans REAPER 7.80 (interface réelle).
   Validés : sans ReaImGui (message clair), aspect visuel (maquette C).
2. **Publier** : dépôt GitHub, `reapack-index --commit` pour générer `index.xml`, CI verte.

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
