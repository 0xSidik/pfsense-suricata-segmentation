#!/usr/bin/env bash
# Scans utilisés pour provoquer des alertes Suricata.
# LAB UNIQUEMENT : ne jamais lancer contre un système qui ne vous appartient pas.
# Cible utilisée dans le projet : l'adresse WAN de pfSense (192.168.100.14),
# derrière laquelle le serveur web DMZ est publié (ports 80/443).
set -u
TARGET="${1:-192.168.100.14}"

echo "[T6] Scan SYN tous ports + scripts NSE 'vuln' (durée observée : 702,68 s)"
nmap -sS -Pn -p1-65535 -T4 --script vuln "$TARGET"

echo "[T7] Détection de services sur les 1000 premiers ports"
date && nmap -sV -Pn -p1-1000 "$TARGET"

echo "Résultat attendu côté détection : alerte 'ET SCAN Possible Nmap User-Agent Observed' (SID 2024364)"
echo "  - GUI : Services > Suricata > Alerts (instance DMZ)"
echo "  - Serveur : tail -f /var/log/suricata-eve.log"
