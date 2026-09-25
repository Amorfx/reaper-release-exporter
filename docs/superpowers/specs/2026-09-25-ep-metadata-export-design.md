# Release Exporter — Export d'EP avec métadonnées pour REAPER

- **Date** : 2026-09-25
- **Statut** : design validé, en attente de relecture de la spec
- **Nom de travail** : *Release Exporter* (script `Release Exporter.lua`)

## 1. Contexte et objectif

La fenêtre native *Render Metadata* de REAPER est pénible à remplir pour un projet
multi-titres : les métadonnées par morceau passent par une syntaxe dans les noms de
régions (`#TITLE=…|ISRC=…`) combinée à des wildcards (`$region(TITLE)`,
`$regionnumber`) et au *Region Render Matrix*.

**Objectif** : un script REAPER à l'interface moderne qui permet de renseigner les
métadonnées d'un EP et de ses morceaux, puis d'exporter tout l'EP en un clic.

**Public** : l'auteur d'abord, puis la communauté REAPER (distribution publique via
ReaPack). L'outil ne doit donc dépendre d'aucune configuration personnelle.

**Critère de succès** : pour un EP de 5 titres déjà découpé en régions, renseigner
l'ensemble des métadonnées et lancer l'export en moins de 2 minutes, sans ouvrir
la fenêtre *Render Metadata* native.

## 2. Décisions de cadrage

| Sujet | Décision |
|---|---|
| Organisation du projet | **Un projet « EP », une région par morceau.** Les mixes sont importés en audio ou en *subprojects*. Le rendu multi-projets est hors périmètre. |
| Formats de sortie | **WAV (principal) + MP3 ou FLAC (secondaire)**, produits en un seul rendu via le format secondaire de REAPER. |
| Approche de rendu | **Le script pilote le rendu région par région** (approche A) plutôt que de configurer les wildcards natifs. |
| Interface | **ReaImGui**, disposition « tout sur un écran » : fiche EP + tableau des morceaux + barre d'export. |
| Version minimale | **REAPER 7.0** (format secondaire, ID3 dans le WAV, `MARKER_GUID`). |

## 3. Métadonnées gérées

### 3.1 Niveau EP (saisies une fois)

| Champ | Obligatoire | Remarque |
|---|---|---|
| Artiste | oui | |
| Artiste de l'album | non | Vide → reprend *Artiste* |
| Titre de l'EP | oui | |
| Année / date de sortie | oui | `AAAA` ou `AAAA-MM-JJ` |
| Genre | non | |
| Label | non | |
| Copyright | non | Ex. `℗ 2026 Nom` |
| Pochette | non | Chemin vers un JPEG/PNG |

### 3.2 Niveau morceau (une ligne par région)

| Champ | Obligatoire | Remarque |
|---|---|---|
| Inclure | — | Case à cocher, cochée par défaut |
| Numéro | — | Calculé : rang parmi les régions **incluses**, triées par position ; `n/total` |
| Titre | oui | **= nom de la région** (synchronisé dans les deux sens) |
| Artiste | non | Vide → reprend l'artiste de l'EP (affiché en grisé) |
| ISRC | non | Validé s'il est renseigné (cf. §7) |
| Compositeur | non | |

### 3.3 Hors périmètre v1

BPM, tonalité, paroles, commentaires, mention *explicit*, UPC/EAN, queue de réverb
(on rend exactement les bornes de la région), normalisation intégrée (on respecte
les réglages de rendu REAPER de l'utilisateur).

## 4. Correspondance avec les tags

Le `metadata_mapper` écrit **explicitement chaque schéma** pour ne pas dépendre des
correspondances implicites de REAPER entre schémas.

| Champ | ID3 (MP3, WAV) | Vorbis (FLAC) | RIFF INFO (WAV) |
|---|---|---|---|
| Titre | `TIT2` | `TITLE` | `INAM` |
| Artiste (morceau, avec repli) | `TPE1` | `ARTIST` | `IART` |
| Artiste de l'album | `TPE2` | `ALBUMARTIST` | — |
| Titre de l'EP | `TALB` | `ALBUM` | `IPRD` |
| Année / date | `TYER` | `DATE` | `ICRD` |
| Genre | `TCON` | `GENRE` | `IGNR` |
| Numéro | `TRCK` (`n/total`) | `TRACKNUMBER` + `TRACKTOTAL` | `ITRK` |
| Label | `TPUB` | `ORGANIZATION` | — |
| Copyright | `TCOP` | `COPYRIGHT` | `ICOP` |
| ISRC | `TSRC` | `ISRC` | — |
| Compositeur | `TCOM` | `COMPOSER` | — |
| Pochette | `APIC_FILE` (+ `APIC_TYPE` = 3, couverture) | via l'image de métadonnées REAPER | — |

Chaque entrée est écrite via
`GetSetProjectInfo_String(proj, "RENDER_METADATA", "<SCHEMA>:<TAG>|<valeur>", true)`.

**Première tâche d'implémentation** : confirmer empiriquement les identifiants exacts
qu'attend REAPER (notamment `TYER` vs `TDRC`, le libellé des schémas Vorbis et INFO,
et la clé qui pilote l'image des FLAC). Méthode : remplir la fenêtre native, puis
lister les identifiants via `GetSetProjectInfo_String(proj, "RENDER_METADATA", "", false)`.
Le tableau ci-dessus est corrigé en conséquence avant d'écrire le mapper.

## 5. Architecture

### 5.1 Distribution

- Dépôt GitHub public servant de **dépôt ReaPack** (`index.xml` généré par
  `reapack-index`).
- Dépendance unique : **ReaImGui** (ReaTeam Extensions). Au lancement, `main`
  vérifie sa présence (`reaper.ImGui_GetBuiltinPath` / `ImGui_CreateContext`) et
  affiche un message explicite s'il est absent.
- Une bibliothèque JSON en Lua pur (ex. `rxi/json.lua`, licence MIT) est intégrée
  au dépôt pour sérialiser les données.

### 5.2 Modules

```
Release Exporter.lua          -- point d'entrée (main)
release_exporter/
  model.lua                   -- pur : données, repli, numérotation, validation, noms de fichiers
  metadata_mapper.lua         -- pur : morceau fusionné → liste de "SCHEMA:TAG|valeur"
  regions.lua                 -- adaptateur REAPER : lecture/écriture des régions + identité
  project_store.lua           -- adaptateur REAPER : persistance ProjExtState
  renderer.lua                -- adaptateur REAPER : sauvegarde/rendu/restauration
  ui/
    ep_panel.lua              -- fiche EP + pochette
    tracks_table.lua          -- tableau des morceaux
    export_bar.lua            -- récapitulatif + bouton Exporter
    settings_popup.lua        -- réglages d'export
    report_popup.lua          -- rapport de fin d'export
  vendor/json.lua
tests/                        -- busted, modules purs uniquement
docs/testing.md               -- checklist de tests manuels
```

Les modules `model` et `metadata_mapper` n'appellent **jamais** l'API `reaper` et
sont donc testables en Lua standard.

### 5.3 Identité des régions

- Identifiant stable = **GUID de la région**, lu via
  `GetSetProjectInfo_String(proj, "MARKER_GUID:<idx>")`, où `<idx>` est l'index
  d'énumération de `EnumProjectMarkers3`. Cet appel est disponible sur toutes les
  versions 7.x. La nouvelle API `GetRegionOrMarker` (≥ 7.62) n'est pas utilisée en
  v1 : son index interne n'est pas documenté comme identique à celui de
  l'énumération, et `MARKER_GUID` suffit. Le reste du code ne voit que des GUID.

### 5.4 Persistance

Stockage dans le projet via `SetProjExtState(proj, "ReleaseExporter", clé, json)` :

| Clé | Contenu |
|---|---|
| `schema_version` | Entier, pour migrer le format plus tard |
| `ep` | Champs EP (§3.1) |
| `track:<GUID>` | `{ include, artist, isrc, composer }` (le titre vient du nom de région) |
| `settings` | Réglages d'export du projet (§6.1) |

- Chaque modification est enregistrée immédiatement, puis `MarkProjectDirty(proj)`
  est appelé pour que Ctrl+S sauvegarde aussi les métadonnées.
- Les derniers réglages d'export sont aussi copiés en global (`SetExtState(…, persist=true)`)
  et servent de valeurs par défaut pour un nouveau projet.
- Les entrées `track:<GUID>` dont la région a disparu sont **conservées** (un
  Ctrl+Z qui restaure la région restaure aussi ses métadonnées). Pas d'interface
  de purge en v1.

### 5.5 Flux de données

```
Régions (ordre, bornes, titre) ─┐
                                ├─► model (fusion + repli + numérotation) ─► UI
ProjExtState (EP, morceaux) ────┘                  │
                                                   ▼ Export
                             validation ─► metadata_mapper ─► renderer ─► rapport
```

## 6. Export

### 6.1 Réglages (fenêtre ⚙)

| Réglage | Défaut |
|---|---|
| Dossier de sortie | `<dossier du projet>/Exports/<Titre de l'EP>` |
| Modèle de nom | `{nn} - {title}` ; balises : `{nn}` (01), `{n}` (1), `{title}`, `{artist}`, `{album}`, `{year}` |
| Format principal | WAV 24 bits, fréquence du projet (16/24 bits ; projet / 44,1 / 48 kHz) |
| Format secondaire | MP3 320 kb/s CBR (choix : MP3 320, FLAC, aucun) |

- Les caractères interdits dans les noms de fichiers (`/ \ : * ? " < > |`), ainsi
  que `$` (réservé aux wildcards REAPER) et `;` (séparateur de `RENDER_TARGETS`),
  sont remplacés par `-`. Les espaces et points en fin de nom sont supprimés.
- Seuls les réglages nécessaires sont modifiés : bornes, dossier, nom, formats,
  métadonnées et le drapeau *embed metadata* (`RENDER_SETTINGS & 512`). Le dither,
  la normalisation, le rééchantillonnage, etc. restent ceux de l'utilisateur. Le
  mode « source » est forcé sur *master mix* (`RENDER_SETTINGS & 3 == 0`, sans
  matrice ni stems). « Ajouter les fichiers rendus au projet »
  (`RENDER_ADDTOPROJ & 1`) est désactivé pendant l'export.

### 6.2 Déroulé

1. **Validation** (`model`) :
   - **Erreurs bloquantes** (ligne surlignée, bouton désactivé) : aucune région
     incluse, titre vide, ISRC mal formé, artiste ou titre de l'EP vide, année
     invalide, dossier de sortie impossible à créer, deux morceaux produisant le
     même nom de fichier.
   - **Avertissements** (non bloquants) : ISRC manquant, pochette absente,
     fichier de pochette introuvable.
2. **Récapitulatif** : « N morceaux → M fichiers dans `<dossier>` ». Si des fichiers
   existent déjà, on demande s'il faut les écraser. Si oui, ils sont supprimés juste
   avant le rendu du morceau concerné, pour que REAPER n'ouvre pas sa propre
   boîte de dialogue d'écrasement. Si non, l'export est annulé.
3. **Rendu** (`renderer`) :
   1. Sauvegarde de l'état complet : `RENDER_SETTINGS`, `RENDER_ADDTOPROJ`,
      `RENDER_SRATE`, `RENDER_BOUNDSFLAG`,
      `RENDER_STARTPOS`, `RENDER_ENDPOS`, `RENDER_TAILFLAG`, `RENDER_FILE`,
      `RENDER_PATTERN`, `RENDER_FORMAT`, `RENDER_FORMAT2`, et toutes les entrées
      `RENDER_METADATA` existantes.
   2. Pour chaque région incluse, dans l'ordre :
      - `RENDER_BOUNDSFLAG = 0`, `RENDER_STARTPOS`/`RENDER_ENDPOS` = bornes de la
        région, `RENDER_TAILFLAG = 0` ;
      - `RENDER_FILE` = dossier, `RENDER_PATTERN` = nom calculé (sans extension ;
        `$` a déjà été remplacé, cf. §6.1) ;
      - `RENDER_FORMAT` / `RENDER_FORMAT2` selon les réglages ;
      - effacement puis écriture des métadonnées du morceau ;
      - `Main_OnCommand(42230, 0)` (*Render project, using the most recent render
        settings, auto-close render dialog*) ;
      - vérification que les fichiers attendus existent et ne sont pas vides.
   3. Restauration de l'état sauvegardé, **dans tous les cas** (boucle exécutée
      dans un `pcall`).
   - En cas d'échec sur un morceau, on continue avec les suivants et on le note
     dans le rapport.
4. **Rapport** : liste des fichiers produits, statut par morceau, bouton
   « Ouvrir le dossier ».

**Conséquence assumée** : N rendus successifs au lieu d'un seul. C'est négligeable
pour 4 à 8 titres.

**Configuration des formats** : `RENDER_FORMAT` accepte soit une configuration
base64, soit un code à 4 caractères (`evaw`, `l3pm`, `calf`) qui applique les
réglages par défaut du format. Pour imposer la profondeur de bits et le débit MP3,
`renderer` embarque des configurations base64 de référence, capturées depuis
REAPER pendant l'implémentation (une par préréglage proposé en §6.1).

## 7. Validation

- **ISRC** : 12 caractères une fois les tirets retirés et le texte passé en
  majuscules, au format `^[A-Z]{2}[A-Z0-9]{3}[0-9]{2}[0-9]{5}$`. On l'enregistre
  normalisé, sans tirets.
- **Année** : `^\d{4}$` ou `^\d{4}-\d{2}-\d{2}$`.
- **Doublons de noms** : détectés après calcul des noms de fichiers.

## 8. Synchronisation et cas limites

- À chaque image, l'UI compare `GetProjectStateChangeCount(proj)` avec la dernière
  valeur connue. Les régions ne sont relues qu'en cas de changement.
- **Projet actif changé** (`EnumProjects(-1)` renvoie un autre projet) → rechargement.
- **Région renommée dans la timeline** → titre mis à jour.
- **Région ajoutée** → nouvelle ligne, cochée.
- **Région déplacée** → réordonnancement et renumérotation.
- **Titre modifié dans l'outil** → région renommée, avec un point d'annulation
  REAPER (`Undo_BeginBlock` / `Undo_EndBlock`).
- **Limite documentée** : les autres champs (stockés en ProjExtState) ne passent
  pas par l'historique d'annulation de REAPER.
- **Projet sans région** : écran vide avec le bouton **« Créer une région par item
  sélectionné »**. Chaque région prend les bornes de l'item et le nom de sa prise
  active, et le tout forme un seul point d'annulation.

## 9. Interface

Disposition validée (option A de la maquette) :

1. **Fiche EP** : zone de pochette (glisser-déposer d'un fichier image ou bouton
   « Choisir… »), puis les champs de §3.1 sur deux lignes.
2. **Tableau des morceaux** : colonnes ☑, #, Titre, Artiste, ISRC, Compositeur,
   Durée. Navigation au clavier : Tab passe à la cellule suivante, Entrée valide.
   Une cellule vide qui hérite de l'EP affiche la valeur héritée en grisé. Les
   erreurs de validation sont surlignées.
3. **Barre d'export** : résumé (formats, dossier, exemple de nom), bouton ⚙ et
   bouton principal « Exporter l'EP (N) ».

Thème : celui de ReaImGui par défaut (sombre), sans personnalisation lourde en v1.

Langue de l'interface : **anglais**, puisque l'outil est destiné à la communauté
REAPER internationale. La maquette validée était en français, mais seule sa
disposition a été retenue.

## 10. Tests

- **Unitaires (busted, Lua 5.4, hors REAPER)** pour `model` et `metadata_mapper` :
  repli d'artiste, numérotation limitée aux régions incluses, validation ISRC et
  année, nettoyage et doublons de noms de fichiers, génération complète des tags
  pour chaque schéma.
- **CI GitHub Actions** : `busted`, `luacheck`, vérification de l'index ReaPack.
- **Tests manuels** (`docs/testing.md`) sur un projet d'exemple de 3 régions :
  export WAV+MP3 puis WAV+FLAC ; contrôle des tags et de la pochette avec
  `ffprobe` ; restauration des réglages de rendu après un export réussi et après
  une annulation ; synchronisation (renommer, déplacer, supprimer puis Ctrl+Z une
  région) ; projet sans région.

## 11. Risques

| Risque | Mitigation |
|---|---|
| Identifiants de métadonnées REAPER différents de ceux supposés | Vérification empirique en première tâche (§4) |
| Réglages de rendu utilisateur non restaurés après un crash | Sauvegarde complète et `pcall`. Un crash de REAPER lui-même reste hors de notre contrôle. |
| Configurations base64 des formats dépendantes de la version REAPER | Capturées sur REAPER 7.0 et testées sur la dernière version ; repli sur les codes à 4 caractères |
| Action 42230 qui affiche malgré tout une boîte de dialogue (ex. écrasement de fichier) | Écrasement confirmé en amont par notre propre dialogue, fichiers existants supprimés avant le rendu |
| Performance de l'UI avec la boucle `defer` | Relecture des régions conditionnée par `GetProjectStateChangeCount` |
