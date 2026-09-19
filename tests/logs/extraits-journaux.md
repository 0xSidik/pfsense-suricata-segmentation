# Extraits de journaux (transcrits depuis les captures)

Ces lignes ont été **retranscrites à la main** depuis les captures d'écran du dépôt (elles ne sont pas des exports de fichiers). En cas de doute, la capture fait foi. Remplacer par des extraits copiés directement depuis `srv-syslog` (`sed -n '1,20p' /var/log/firewall.log`) si les fichiers d'origine sont disponibles.

## 1. Blocage LAN → DMZ (règle « Bloc LAN vers DMZ », tracker 1788634015)

Capture : `screenshots/64-journalisation-blocage-lan-vers-dmz.png`

```text
Sep  7 02:33:09 _gateway filterlog[23721]: 93,,,1788634015,vtnet1.10,match,block,in,4,0x0,,64,58663,0,DF,1,icmp,84,10.10.10.101,10.10.30.6,request,33151,3264
```

## 2. Blocage DMZ → LAN (règle « Bloc DMZ vers LAN », tracker 1788636548)

Capture : `screenshots/61-preuves-syslog-blocages-et-alertes.png` (`srv-web` exécute `ping 10.10.10.101`)

```text
Sep  7 00:50:21 _gateway filterlog[23721]: 101,,,1788636548,vtnet1.30,match,block,in,4,0x0,,64,36393,0,DF,1,icmp,84,10.10.30.6,10.10.10.101,request,1,4464
```

## 3. Blocage DMZ → DNS externe (règle finale de la DMZ, tracker 1788636617)

Même capture (seuls les champs principaux sont repris) :

| Heure | Interface | Action | Protocole | Source → destination |
|---|---|---|---|---|
| 00:50:22 | `vtnet1.30` | block | tcp | 10.10.30.6 → 8.8.8.8:53 |
| 00:50:29 | `vtnet1.30` | block | tcp | 10.10.30.6 → 1.1.1.1:53 |

## 4. Refus implicite LAN → DNS externe (règle `1000000103`)

Capture : `screenshots/64-…` et `61-…`

| Heure | Interface | Action | Protocole | Source → destination |
|---|---|---|---|---|
| 02:33:09 | `vtnet1.10` | block | udp | 10.10.10.100 → 8.8.8.8:53 |
| 02:33:09 | `vtnet1.10` | block | udp | 10.10.10.100 → 1.1.1.1:53 |

## 5. Alerte Suricata reçue sur `srv-syslog`

Capture : `screenshots/61-preuves-syslog-blocages-et-alertes.png` (`/var/log/suricata-eve.log`)

```text
Sep  7 00:42:24 _gateway suricata[31279]: [1:2024364:4] ET SCAN Possible Nmap User-Agent Observed [Classification: Web Application Attack] [Priority: 1] {TCP} 10.10.10.101:56540 -> 192.168.100.14:80
```

La capture montre une dizaine de lignes similaires à la même seconde (ports sources variables, de 56514 à 56628), produites pendant l'exécution des scripts NSE de Nmap.

## 6. Résultats Nmap (transcrits)

Commande du 7 septembre, 02:13 UTC : `nmap -sV -Pn -p1-1000 192.168.100.14`

```text
Not shown: 997 filtered tcp ports (no-response)
PORT    STATE  SERVICE VERSION
53/tcp  open   domain  Unbound
80/tcp  open   http    nginx 1.18.0 (Ubuntu)
443/tcp closed https
Service Info: OS: Linux; CPE: cpe:/o:linux:linux_kernel
Nmap done: 1 IP address (1 host up) scanned in 30.51 seconds
```

Commande du 7 septembre, 00:30 UTC : `nmap -sS -Pn -p1-65535 -T4 --script vuln 192.168.100.14`

```text
Not shown: 65533 filtered tcp ports (no-response)
PORT   STATE SERVICE
53/tcp open  domain
80/tcp open  http
Nmap done: 1 IP address (1 host up) scanned in 702.68 seconds
```
