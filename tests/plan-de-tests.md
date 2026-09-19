# Plan de tests et résultats

Tous les résultats ci-dessous sont **[RÉEL]** : chacun renvoie à une capture ou un journal du dépôt. Les tests qui **n'ont pas de preuve** dans le dépôt sont regroupés en partie D, à compléter avant de les citer ailleurs.

**Environnement de test** : poste Kali Linux (Nmap 7.99, Hydra v9.6), `10.10.10.101` d'après les journaux (VLAN 10) ; `srv-web` 10.10.30.6 (DMZ) ; `srv-syslog` 10.10.20.5 (SERVEURS). Les horaires sont en UTC.

## A. État initial, avant segmentation (5 septembre 2026)

Tests menés sur le réseau à plat 192.168.1.0/24 (pfSense en configuration initiale, LAN 192.168.1.1/24). Objectif : disposer d'une référence.

| ID | Test | Commande | Résultat observé | Preuve |
|---|---|---|---|---|
| A1 | Scan de ports d'une machine du réseau à plat | `nmap -sS -p1-1000 192.168.1.6` | 22/tcp (ssh) et 80/tcp (http) **ouverts**, 998 fermés ; 1,59 s | Capture d'origine non publiée (voir note) |
| A2 | Attaque par dictionnaire SSH | `hydra -l <compte> -P dico.txt ssh://192.168.1.6` | 1 mot de passe valide trouvé en 3 s (9 essais) | Capture d'origine non publiée (voir note) |
| A3 | Joignabilité d'une seconde machine | `ping 192.168.1.5` puis `curl http://192.168.1.5` | ping : 9/9, 0 % de perte, TTL 64, 1,4 à 3,5 ms ; `curl` : connexion refusée sur le port 80 | [`13-…`](../screenshots/13-baseline-ping-curl-192.168.1.5.png) |
| A4 | Latence ICMP | `ping -c 20 192.168.1.6` | 20/20, 0 % de perte ; RTT min/moy/max/mdev = **1,065 / 2,214 / 3,914 / 0,821 ms** | [`12-…`](../screenshots/12-baseline-ping-20-paquets.png) |
| A5 | Charge pfSense avant test | Widget « System Information » | CPU **3 %**, mémoire 10 % de 4032 MiB, table d'états 14 042 / 403 000 | [`10-…`](../screenshots/10-baseline-cpu-avant-test.png) |
| A6 | Charge pfSense pendant test | idem | CPU **9 %**, mémoire 10 %, table d'états 6 191 / 403 000 | [`11-…`](../screenshots/11-baseline-cpu-pendant-test.png) |

> **Note sur A1 et A2** : la capture d'origine (« Test Avant 1 et 2 ») montre un nom de compte et un mot de passe partiellement flouté. Elle n'est **pas** incluse dans le dépôt. Refaire la capture avec un compte de test jetable et un masquage complet, puis l'ajouter sous `screenshots/14-baseline-nmap-hydra.png`. Les résultats ci-dessus sont ceux lus sur la capture d'origine.

**Conclusion [RÉEL]** : sur le réseau à plat, le scan aboutit et le mot de passe SSH est retrouvé : aucune séparation ni détection.

## B. Après segmentation, avant Suricata (5 – 6 septembre 2026)

| ID | Test | Commande | Résultat observé | Preuve |
|---|---|---|---|---|
| B1 | Interfaces pfSense | Statut > Interfaces | WAN `192.168.100.14/24` (passerelle 192.168.100.2, DHCP), LAN `10.10.10.1`, DMZ `10.10.30.1`, SERVEURS `10.10.20.1`, toutes `up`, 0 erreur | [`22-…`](../screenshots/22-pfsense-interfaces-actives-par-zone.png) |
| B2 | Tableau de bord au repos | Widget « System Information » (6 sept., 02:24 UTC) | CPU **3 %**, mémoire 9 % de 4032 MiB, disque 4 % de 16 Go (ZFS), 4 interfaces `up` | [`28-…`](../screenshots/28-dashboard-au-repos-4-interfaces.png) |
| B3 | Temps de réponse HTTP vers le web DMZ via le WAN | `for i in {1..10}; do curl -4 -o /dev/null -s -w "Essai $i : %{time_total}s\n" http://192.168.100.14; done` | 10 essais entre **12,3 et 17,2 ms** (le plus souvent ≈ 13 ms) | [`30-…`](../screenshots/30-mesure-curl-web-dmz-via-wan.png) |
| B4 | Temps de réponse HTTP vers Internet | même boucle sur `http://google.com` | 9 essais entre **159 et 239 ms**, 1 essai à **1,845 s** | [`31-…`](../screenshots/31-mesure-curl-google.png) |
| B5 | Charge pfSense sous charge légère | Widget (6 sept., 02:45 UTC) | CPU **16 %**, mémoire 9 %, table d'états 4 | [`29-…`](../screenshots/29-cpu-charge-legere-16pct.png) |

## C. Après déploiement de Suricata et de la journalisation (6 – 7 septembre 2026)

| ID | Test | Commande / action | Résultat attendu | Résultat observé | Preuve |
|---|---|---|---|---|---|
| C1 | LAN → DMZ, HTTP | `curl http://10.10.30.6` depuis le poste de test | Bloqué | `curl: (28) Failed to connect to 10.10.30.6 port 80 after 133305 ms` | [`60-…`](../screenshots/60-test-lan-vers-dmz-curl-timeout.png) |
| C2 | LAN → DMZ, ICMP | `ping 10.10.30.6` | Bloqué et journalisé | Aucune réponse ; ligne `block` de la règle `1788634015` sur `vtnet1.10` (source 10.10.10.101 → 10.10.30.6) | [`64-…`](../screenshots/64-journalisation-blocage-lan-vers-dmz.png) |
| C3 | DMZ → LAN, ICMP | `ping 10.10.10.101` depuis `srv-web` | Bloqué et journalisé | Lignes `block` de la règle `1788636548` sur `vtnet1.30` (10.10.30.6 → 10.10.10.101), reçues sur `srv-syslog` | [`61-…`](../screenshots/61-preuves-syslog-blocages-et-alertes.png) |
| C4 | DMZ → DNS externe | requêtes depuis `srv-web` vers 8.8.8.8 et 1.1.1.1 (port 53) | Bloqué par la règle finale | Lignes `block` de la règle `1788636617` (10.10.30.6 → 8.8.8.8:53 et 1.1.1.1:53) | [`61-…`](../screenshots/61-preuves-syslog-blocages-et-alertes.png) |
| C5 | LAN → DNS externe | requêtes du poste 10.10.10.100 vers 8.8.8.8 et 1.1.1.1 | Bloqué (seul le DNS pfSense est autorisé) | Lignes `block` de la règle `1000000103` (refus implicite) sur `vtnet1.10` | [`64-…`](../screenshots/64-journalisation-blocage-lan-vers-dmz.png) |
| C6 | Scan complet + scripts « vuln » | `nmap -sS -Pn -p1-65535 -T4 --script vuln 192.168.100.14` (7 sept., 00:30) | Ports filtrés, alertes | 65 533 ports **filtrés** ; 53/tcp `domain` et 80/tcp `http` ouverts ; terminé en **702,68 s** | [`61-…`](../screenshots/61-preuves-syslog-blocages-et-alertes.png) |
| C7 | Identification des services | `nmap -sV -Pn -p1-1000 192.168.100.14` (7 sept., 02:13) | Services exposés = ceux publiés | 53/tcp Unbound ; 80/tcp **nginx 1.18.0 (Ubuntu)** ; 443/tcp **fermé** ; 997 filtrés ; 30,51 s | [`63-…`](../screenshots/63-nmap-sv-192.168.100.14.png) |
| C8 | Détection du scan par Suricata (interface) | Services > Suricata > Alerts, instance DMZ | Alerte | 4 alertes affichées à 02:13:49 : `ET SCAN Possible Nmap User-Agent Observed`, GID:SID `1:2024364`, priorité 1, TCP, 10.10.10.101 → 10.10.30.6:80 | [`62-…`](../screenshots/62-alerte-suricata-dmz-nmap.png) |
| C9 | Centralisation de l'alerte | `tail -f /var/log/suricata-eve.log` sur `srv-syslog` | Alerte reçue | Lignes de 00:42:24 : `[1:2024364:4] ET SCAN Possible Nmap User-Agent Observed [Classification: Web Application Attack] [Priority: 1] {TCP} 10.10.10.101:56540 -> 192.168.100.14:80` | [`61-…`](../screenshots/61-preuves-syslog-blocages-et-alertes.png) |
| C10 | Centralisation des blocages | `tail -f /var/log/firewall.log` sur `srv-syslog` | Blocages reçus | Lignes `filterlog` ci-dessus reçues avec le champ hôte `_gateway` | [`61-…`](../screenshots/61-preuves-syslog-blocages-et-alertes.png) |

Extraits de journaux transcrits : [`logs/extraits-journaux.md`](logs/extraits-journaux.md).

### Points d'interprétation [RÉEL]

- **La source des scans est `10.10.10.101` (VLAN 10)**, et la cible est l'adresse WAN de pfSense (192.168.100.14). Le scan n'a donc pas été lancé depuis un réseau externe au sens strict*.
- **Les scans ont abouti** (C6, C7 terminés). Les captures ne montrent **pas** de blocage de l'hôte par Suricata : l'action affichée est « alerte » (C8).
- **Le port 53/tcp (Unbound) répond sur 192.168.100.14** (C6, C7). Le résolveur DNS est configuré sans restriction d'interface (`active_interface` vide dans l'export). Le scan venant du LAN, où une règle autorise le DNS vers toutes les adresses de pfSense, cela ne prouve pas une exposition depuis le WAN. À vérifier depuis une machine réellement côté WAN **[À CONFIRMER]**.
- **Le port 443 est fermé sur le serveur web** (C7) : la redirection 443 existe, mais nginx n'y écoute pas.

## D. Tests sans preuve dans ce dépôt [À RÉALISER ou À DOCUMENTER]

Ces éléments apparaissent dans d'autres documents du projet mais **aucun fichier fourni ne les établit**. Ne pas les publier tels quels sans preuve.

| ID | Test / indicateur | Ce qu'il faut fournir |
|---|---|---|
| D1 | Attaque par dictionnaire SSH **après** déploiement (Hydra vers `srv-web` ou depuis une zone filtrée) | Commande, résultat, alerte Suricata associée |
| D2 | Blocage effectif d'une source par Suricata (onglet *Blocks*) | Capture de l'onglet *Blocks*, test hors liste de passage |
| D3 | Latence et charge CPU **avec** Suricata actif | Même protocole que B3 à B5, avec captures |
| D4 | Nombre de règles chargées | Capture ou sortie du chargement des règles |
| D5 | Taux de scénarios réussis, taux de faux positifs, nombre d'événements bloqués | Tableau de résultats brut (journaux exportés) |
| D6 | Comparaison de débit entre outils de détection | Protocole et mesures (ex. iperf3) |
| D7 | Test d'accès depuis un vrai hôte WAN vers 80, 443, 53 | Scan depuis une machine côté WAN, avec sa source indiquée |

## Synthèse des mesures [RÉEL]

| Mesure | Avant segmentation | Après segmentation, sans Suricata |
|---|---|---|
| Latence ICMP moyenne (20 paquets) | 2,214 ms | non mesurée |
| Temps HTTP vers le web DMZ via WAN | non applicable | ≈ 13 ms (12,3 – 17,2 ms) |
| Temps HTTP vers google.com | non mesuré | 159 – 239 ms (+1 valeur à 1,845 s) |
| CPU pfSense | 3 % (repos), 9 % (test) | 3 % (repos), 16 % (charge légère) |

Aucune mesure « avec Suricata » n'est disponible (voir D3).
