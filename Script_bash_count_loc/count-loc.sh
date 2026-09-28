#!/bin/bash
# count-loc.sh — Compte les lignes de code source d'un dossier (mesure LOC).
#
# Usage : ./count-loc.sh [dossier]      (dossier courant par défaut)
#
# Ce qui est compté : uniquement le code source (fichiers de logique).
# Ce qui est exclu :
#   - dossiers de dépendances, de build et de l'IDE (node_modules, vendor, target, build, dist...)
#   - fichiers de configuration et de données (json, yml, xml, properties, lockfiles...)
#   - fichiers générés ou minifiés (*.min.js, *.min.css)
# Pour chaque ligne, on distingue : ligne vide / commentaire / code.
# LOC = lignes de code (ni vides, ni commentaires).

DIR="${1:-.}"

# Extensions considérées comme du code source (à adapter selon le projet)
EXTS="java c h cpp hpp cc cs py js jsx ts tsx php kt go rs rb swift scala sh"

# Dossiers ignorés
EXCLUDED_DIRS="node_modules vendor target build dist out bin obj venv .venv __pycache__ .idea .vscode .gradle .git coverage"

# Construction de la commande find
prune=()
for d in $EXCLUDED_DIRS; do prune+=(-name "$d" -o); done
names=()
for e in $EXTS; do names+=(-name "*.$e" -o); done

# Étape 1 : comptage par fichier. xargs peut lancer awk plusieurs fois
# s'il y a beaucoup de fichiers, donc chaque awk n'affiche que des lignes brutes
# (ext fichiers total vides commentaires code), additionnées à l'étape 2.
find "$DIR" \( "${prune[@]}" -false \) -prune -o \
     -type f \( "${names[@]}" -false \) \
     ! -name '*.min.js' ! -name '*.min.css' -print0 |
xargs -0 -r awk '
  # Nouveau fichier : on détermine le style de commentaire selon l extension
  FNR == 1 {
    ext = FILENAME; sub(/.*\./, "", ext)
    files[ext]++
    hash_style = (ext == "py" || ext == "rb" || ext == "sh")
    in_block = 0
  }
  {
    line = $0
    sub(/\r$/, "", line)                     # fins de ligne Windows
    gsub(/^[ \t]+|[ \t]+$/, "", line)
    total[ext]++

    if (in_block) {                          # dans un commentaire /* ... */
      comment[ext]++
      if (index(line, "*/")) in_block = 0
      next
    }
    if (line == "") { blank[ext]++; next }

    if (hash_style) {
      if (line ~ /^#/) { comment[ext]++; next }
    } else {
      if (line ~ /^\/\//) { comment[ext]++; next }
      if (ext == "php" && line ~ /^#/) { comment[ext]++; next }
      if (line ~ /^\/\*/) {
        rest = substr(line, 3)
        p = index(rest, "*/")
        if (p == 0) { in_block = 1; comment[ext]++; next }
        if (substr(rest, p + 2) ~ /^[ \t]*$/) { comment[ext]++; next }
      }
      # commentaire bloc ouvert en fin de ligne de code
      q = index(line, "/*")
      if (q > 0 && index(substr(line, q + 2), "*/") == 0) in_block = 1
    }
    code[ext]++
  }
  END {
    for (e in files) print e, files[e], total[e] + 0, blank[e] + 0, comment[e] + 0, code[e] + 0
  }
' |
# Étape 2 : somme par extension et affichage du tableau
awk '
  { files[$1] += $2; total[$1] += $3; blank[$1] += $4; comment[$1] += $5; code[$1] += $6 }
  END {
    printf "%-8s %7s %9s %8s %11s %9s\n", "Ext", "Fich.", "Total", "Vides", "Comment.", "LOC"
    for (e in files) {
      printf "%-8s %7d %9d %8d %11d %9d\n", e, files[e], total[e], blank[e], comment[e], code[e]
      F += files[e]; T += total[e]; B += blank[e]; C += comment[e]; L += code[e]
    }
    printf "%-8s %7d %9d %8d %11d %9d\n", "TOTAL", F, T, B, C, L
    if (L + C > 0) printf "\nCommentaires : %.1f %% des lignes non vides (utile pour le MI)\n", 100 * C / (L + C)
  }
'
