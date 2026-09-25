# Avancement — Release Exporter

_Dernière mise à jour : 2026-09-25_

## Fait
- Spec et plan : `docs/superpowers/specs/2026-09-25-ep-metadata-export-design.md`, `docs/superpowers/plans/2026-09-25-release-exporter.md`.
- Tâches 1 à 9 du plan implémentées (branche `feat/release-exporter`), 73 tests unitaires verts, luacheck propre.
- Relecture complète par un relecteur indépendant : 2 critiques et 6 importants corrigés, avec tests.
- Vérifications REAPER 7.80 (`docs/reaper-api-notes.md`) : GUID des régions, casse des clés ExtState, `RENDER_TARGETS`,
  identifiants de tags confirmés par exiftool sur de vrais rendus (MP3, WAV, FLAC), pochette MP3/WAV/FLAC.

## Reste à faire
1. **Capturer les presets MP3 320 CBR et FLAC 24 bits.** Les mettre en format *principal*, cliquer sur *Save settings*,
   lancer `tools/inspect_render_state.lua` et relever `RENDER_FORMAT`. Les copier dans
   `Rendering/release_exporter/formats.lua`, puis relancer `tools/probe_render_e2e.lua` et vérifier avec exiftool.
2. **Dérouler la checklist manuelle** `docs/testing.md` dans REAPER (interface réelle).
3. **Publier** : dépôt GitHub, `reapack-index --commit` pour générer `index.xml`, CI verte.

## Points mineurs reportés (relecture)
- Les jobs et l'existence de la pochette sont recalculés à chaque image (à déplacer dans `rebuild`).
- La vérification de la pochette utilise un chemin brut dans l'app et un chemin nettoyé dans la validation.
- Le type d'image de la pochette déposée n'est pas vérifié.
- Les noms réservés Windows et les noms trop longs ne sont pas nettoyés.
- Les dossiers de sortie relatifs ou avec `~` ne sont pas refusés.
- Un dossier impossible à créer n'est détecté qu'à l'export.
- L'avertissement d'écrasement et la suppression ne s'appuient pas sur la même liste de chemins.
- Une région sans GUID est ignorée sans rien signaler.
- Les réglages de rendu restants (canaux, normalisation) ne sont pas affichés dans la confirmation.
- Un brouillon peut rester en mémoire si sa ligne disparaît.
