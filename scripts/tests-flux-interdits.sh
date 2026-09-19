#!/usr/bin/env bash
# Vérifie que les flux interdits par la politique sont bien bloqués.
# LAB UNIQUEMENT. Adapter les variables à votre plan d'adressage.
#
# Partie A - à lancer depuis un poste du LAN (VLAN 10), ex. le poste de test :
#   ./tests-flux-interdits.sh lan
# Partie B - à lancer depuis le serveur web de la DMZ (srv-web) :
#   ./tests-flux-interdits.sh dmz
set -u
DMZ_WEB="10.10.30.6"       # Serveur_Web_DMZ
LAN_HOST="10.10.10.101"    # hôte LAN joignable (poste de test)

case "${1:-}" in
  lan)
    echo "[T2] LAN -> DMZ (HTTP) : doit échouer (délai dépassé)"
    curl --max-time 10 "http://${DMZ_WEB}" ; echo "code retour curl = $?"
    echo "[T3] LAN -> DMZ (ICMP) : doit rester sans réponse"
    ping -c 4 -W 2 "${DMZ_WEB}"
    ;;
  dmz)
    echo "[T4] DMZ -> LAN (ICMP) : doit rester sans réponse"
    ping -c 4 -W 2 "${LAN_HOST}"
    ;;
  *)
    echo "Usage: $0 {lan|dmz}"; exit 1 ;;
esac
echo "Vérifier ensuite les blocages dans /var/log/firewall.log de srv-syslog (champ 'block')."
