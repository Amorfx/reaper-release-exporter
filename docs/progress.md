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
   Validés : sans ReaImGui (message clair), aspect visuel (maquette C), lot 1 (création des régions, fiche,
   pochette JPEG et PNG, renommage et annulation, synchro avec REAPER, ISRC invalide, morceau exclu, persistance).
   Export WAV 24 + MP3 réel vérifié à l'exiftool (tags ID3/RIFF, 320 kbps, 24 bits, pochette PNG identique).
   Considérés comme couverts par les tests automatiques et le rendu de bout en bout (non refaits à la main) :
   réglages de rendu restaurés, FLAC, projet non enregistré, caractères interdits, Save / Save As,
   saisie en cours lors d'un changement d'onglet, fichier verrouillé.
   Restent à faire à la main : annulation d'un rendu, long export (8 morceaux), autre projet dans le même onglet,
   changement d'onglet.
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
