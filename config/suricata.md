# Configuration Suricata

Source : [`pfsense-config-assainie.xml`](pfsense-config-assainie.xml), section `installedpackages/suricata`, et captures `screenshots/40-…` à `45-…`. Tout est **[RÉEL]** sauf mention contraire.

## Installation

| Élément | Valeur | Preuve |
|---|---|---|
| Paquet | `pfSense-pkg-suricata` 7.0.2, moteur `suricata-7.0.2_1` | `screenshots/40-…`, `41-…`, `42-…` |
| Chemin | Système > Gestionnaire de paquets > Paquets disponibles > `suricata` > Install | `screenshots/40-…` |
| Paquets installés | 13 (dont libyaml 0.2.5, libpcap 1.10.4, libnet 1.2,1, nss 3.89.1, nspr 4.35, py311-yaml 6.0) ; 57 MiB d'espace, 11 MiB téléchargés | `screenshots/41-…` |

Le paquet est livré **sans règles** : elles doivent être téléchargées après installation (message affiché à la fin de l'installation, `screenshots/42-…`).

## Paramètres globaux (Services > Suricata > Global Settings)

| Paramètre | Valeur | Remarque |
|---|---|---|
| Jeu de règles ET Open | **Activé** | Emerging Threats Open ; MD5 `c54d129abe82cb1b14376f4a8cb9617d`, mise à jour du 2026-09-06 03:43 UTC (`screenshots/43-…`) |
| ET Pro, Snort VRT, Snort Community, GPLv2, Feodo, ABUSE.ch SSL | Désactivés | |
| Mise à jour automatique des règles | Tous les **7 jours**, à **03:00** (`7d_up`, `03:00`) | |
| Mises à jour « à chaud » (`live_swap_updates`) | Activé | |
| Supprimer les hôtes bloqués | Jamais (`never_b`) | Les blocages restent jusqu'à effacement manuel |
| Effacer les blocages au démarrage/arrêt (`clearblocks`) | Activé | |
| Conserver la configuration à la désinstallation | Activé | |
| Journalisation Suricata vers syslog (global) | Désactivé ; facilité `local1`, priorité `notice` | |

## Instances

Trois instances, une par interface. Configuration finale, état au **7 septembre 2026**.

| Paramètre | WAN (`vtnet0`) | DMZ (`vtnet1.30`) | LAN (`vtnet1.10`) |
|---|---|---|---|
| Activée | oui | oui | oui |
| Mode de blocage | **Legacy Mode** | **Legacy Mode** | **Désactivé** (détection seule) |
| Bloquer les hôtes fautifs (`blockoffenders`) | **oui** | **oui** | non |
| Sens du blocage / kill des états | source et destination (`both`) / oui | idem | (inactif) |
| Blocage limité aux règles « drop » | non | non | non |
| Mode d'exécution | `workers` | `workers` | `autofp` |
| Liste de passage / liste « home » | `default` / `default` | `default` / `default` | `default` / `default` |
| Alertes vers le journal système | **non** | **non** | **oui** (`local1`, `notice`) |
| Journal EVE | **non** | **non** | **oui** (fichier « regular ») |
| Profil du moteur de détection | medium | medium | medium |
| `max_pending_packets` / `flow_memcap` / `stream_memcap` | 1024 / 128 Mo / 256 Mo | idem | idem |

Preuves : [`screenshots/45-suricata-instances-legacy-mode-7sept.png`](../screenshots/45-suricata-instances-legacy-mode-7sept.png) (état final) et [`screenshots/44-suricata-instances-inline-ips-6sept.png`](../screenshots/44-suricata-instances-inline-ips-6sept.png) (état intermédiaire, mode Inline IPS le 6 septembre à 04:11 UTC).

### Historique du mode de blocage

| Date (UTC) | Mode WAN / DMZ | Preuve |
|---|---|---|
| 2026-09-06 04:11 | **Inline IPS** | `screenshots/44-…` |
| 2026-09-07 00:34 | **Legacy Mode** | `screenshots/45-…`, export XML (`ips_mode_legacy`) |


## Jeux de règles activés (identiques sur les trois instances) : 26 fichiers

| Famille | Fichiers |
|---|---|
| Règles ET Open « métier » | `emerging-scan.rules`, `emerging-attack_response.rules`, `emerging-web_server.rules`, `emerging-web_specific_apps.rules` |
| Règles d'événements de protocole/décodeur (Suricata) | `app-layer-events`, `decoder-events`, `stream-events`, `files`, `http-events`, `http2-events`, `tls-events`, `dns-events`, `dhcp-events`, `ftp-events`, `smtp-events`, `ssh-events`, `smb-events`, `nfs-events`, `ntp-events`, `ipsec-events`, `kerberos-events`, `quic-events`, `rfb-events`, `mqtt-events`, `modbus-events`, `dnp3-events` |

## Détection démontrée

| Élément | Valeur |
|---|---|
| Signature | `ET SCAN Possible Nmap User-Agent Observed` |
| Identifiant | GID:SID `1:2024364` (révision 4 dans le journal syslog) |
| Classe / priorité | Web Application Attack / 1 |
| Vue GUI | Services > Suricata > Alerts, instance DMZ : source 10.10.10.101 → 10.10.30.6:80, action « alerte » (`screenshots/62-…`) |
| Vue serveur | `/var/log/suricata-eve.log` de `srv-syslog` : `10.10.10.101:56540 -> 192.168.100.14:80` (`screenshots/61-…`) |

## Points d'attention

**[RÉEL]**

- Seule l'instance **LAN** envoie ses alertes vers syslog et écrit le journal EVE. Les alertes des instances WAN et DMZ ne sont visibles que dans l'interface de Suricata. Pourtant l'alerte du scan a bien été reçue par le serveur : sa destination (192.168.100.14, adresse avant redirection) est cohérente avec une détection par l'instance LAN, mais l'instance émettrice n'est pas indiquée dans les journaux **[À CONFIRMER]**.
- Les lignes reçues sur `srv-syslog` sont au **format texte d'alerte**, pas en JSON, malgré le nom du fichier `suricata-eve.log`.

**[À CONFIRMER]**

- La liste de passage `default` est générée par le paquet et exempte normalement les réseaux locaux de pfSense du blocage. Cela peut expliquer qu'un hôte LAN (10.10.10.101) ait pu terminer ses scans malgré le « Block Offenders » de la DMZ. La composition de la liste et l'onglet *Blocks* ne sont pas dans les preuves.

**[RECOMMANDATION]**

- Activer l'envoi des alertes vers syslog (ou EVE via syslog) sur WAN et DMZ.
- Tester le blocage avec une source **hors** de la liste de passage, et conserver la capture de l'onglet *Blocks*.
