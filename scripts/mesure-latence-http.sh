#!/usr/bin/env bash
# Mesure du temps total d'une requête HTTP (10 essais) - méthode utilisée dans le projet.
# À lancer depuis le poste de test (Kali).
# Usage : ./mesure-latence-http.sh http://192.168.100.14
#         ./mesure-latence-http.sh http://google.com
set -u
URL="${1:?Usage: $0 <url>}"
for i in $(seq 1 10); do
  curl -4 -o /dev/null -s -w "Essai $i : %{time_total}s\n" "$URL"
done
