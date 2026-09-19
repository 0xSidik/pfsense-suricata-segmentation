# Règles de filtrage et NAT pfSense

Source : [`pfsense-config-assainie.xml`](pfsense-config-assainie.xml) (export du 7 septembre 2026, 01:08 UTC). Toutes les valeurs de ce document sont **[RÉEL]** ; les remarques d'analyse sont étiquetées.

**Principe** : pfSense évalue les règles d'une interface **dans l'ordre de la liste, la première règle qui correspond s'applique**. Sans règle correspondante, le trafic est refusé (refus implicite). Aucune règle flottante n'est définie.

## Alias

| Alias | Type | Valeur | Description (config) |
|---|---|---|---|
| `Postes_Admin` | Hôte | `10.10.10.100` | postes autorisés à administrer pfSense |
| `Serveur_Web_DMZ` | Hôte | `10.10.30.6` | serveur Web en DMZ |
| `Serveur_Syslog` | Hôte | `10.10.20.5` | serveur de centralisation des journaux |
| `Admin_Ports` | Ports | `445 3389` | (créé le 2026-09-05 19:00:50 UTC) |

## Redirection de ports (NAT entrant)

| Interface | Proto | Destination | Port | Redirigé vers | Port | Description | Créée (UTC) |
|---|---|---|---|---|---|---|---|
| WAN | TCP | WAN address | 80 | `Serveur_Web_DMZ` | 80 | NAT-WEB-DMZ-80 | 2026-09-05 19:49:06 |
| WAN | TCP | WAN address | 443 | `Serveur_Web_DMZ` | 443 | NAT-WEB-DMZ-443 | 2026-09-05 19:49:43 |

Les règles de filtrage associées sur le WAN (source `any` vers `Serveur_Web_DMZ` 80 / 443) ont été générées automatiquement avec les redirections. Réflexion NAT désactivée (`disablenatreflection = yes`). Aucun mode de NAT sortant explicite dans l'export (comportement automatique par défaut) **[À CONFIRMER]**.

Preuve : [`screenshots/27-nat-port-forward-web-dmz.png`](../screenshots/27-nat-port-forward-web-dmz.png), [`screenshots/65-extrait-xml-nat.png`](../screenshots/65-extrait-xml-nat.png).

## Règles par interface (ordre d'évaluation)

### LAN (`vtnet1.10`, 10.10.10.0/24)

| # | Action | Proto | Source | Destination | Port | Journal | Description | Créée (UTC) |
|---|---|---|---|---|---|---|---|---|
| 0 | Pass | TCP | LAN net | LAN address | 80, 22 | – | *Règle anti-blocage* (implicite pfSense) | – |
| 1 | Pass | TCP/UDP | LAN net | (self) | 53 | non | LAN vers DNS pfSense | 2026-09-06 02:54:57 |
| 2 | **Block** | * | LAN net | 10.10.30.0/24 | * | **oui** | Bloc LAN vers DMZ | 2026-09-05 18:46:55 |
| 3 | Pass | TCP | `Postes_Admin` | 10.10.20.0/24 | 445 | non | Admin SERVEURS RDP/SMB | 2026-09-05 19:10:36 |
| 4 | Pass | TCP | `Postes_Admin` | 10.10.20.0/24 | 3389 | non | Admin SERVEURS RDP/SMB | 2026-09-05 19:13:04 |
| 5 | Pass | TCP | LAN net | any | 80 | non | LAN vers Internet Web | 2026-09-05 19:16:10 |
| 6 | Pass | TCP | LAN net | any | 443 | non | LAN vers Internet Web | 2026-09-05 19:17:10 |
| 7 | Pass | TCP/UDP | LAN net | `Serveur_Syslog` | 514 | non | LAN vers Syslog | 2026-09-05 19:18:19 |

Preuve (état du 5 sept., avant la règle DNS) : [`screenshots/24-regles-lan.png`](../screenshots/24-regles-lan.png).

### DMZ (`vtnet1.30`, 10.10.30.0/24)

| # | Action | Proto | Source | Destination | Port | Journal | Description | Créée (UTC) |
|---|---|---|---|---|---|---|---|---|
| 1 | Pass | TCP | any | `Serveur_Web_DMZ` | 80 | non | Any vers Web DMZ | 2026-09-05 19:26:41 |
| 2 | Pass | TCP | any | `Serveur_Web_DMZ` | 443 | non | Any vers Web DMZ | 2026-09-05 19:26:48 |
| 3 | Pass | TCP/UDP | `Serveur_Web_DMZ` | `Serveur_Syslog` | 514 | non | Web DMZ vers Syslog | 2026-09-05 19:27:50 |
| 4 | **Block** | * | DMZ net | 10.10.10.0/24 | * | **oui** | Bloc DMZ vers LAN | 2026-09-05 19:29:08 |
| 5 | **Block** | * | DMZ net | 10.10.20.0/24 | * | **oui** | Bloc DMZ vers SERVEURS | 2026-09-05 19:29:43 |
| 6 | **Block** | * | DMZ net | any | * | **oui** | Bloc DMZ vers any (finale) | 2026-09-05 19:30:17 |

Preuve : [`screenshots/25-regles-dmz.png`](../screenshots/25-regles-dmz.png).

### SERVEURS (`vtnet1.20`, 10.10.20.0/24)

| # | Action | Proto | Source | Destination | Port | Journal | Description | Créée (UTC) |
|---|---|---|---|---|---|---|---|---|
| 1 | Pass | TCP/UDP | SERVEURS net | (self) | 53 | non | SERVEURS vers DNS pfSense | 2026-09-06 04:21:28 |
| 2 | **Block** | * | SERVEURS net | 10.10.10.0/24 | * | **oui** | Bloc SERVEURS vers LAN | 2026-09-05 19:21:53 |
| 3 | **Block** | * | SERVEURS net | 10.10.30.0/24 | * | **oui** | Bloc SERVEURS vers DMZ | 2026-09-05 19:23:03 |
| 4 | Pass | TCP | SERVEURS net | any | 80 | non | SERVEURS vers Internet MAJ | 2026-09-05 19:24:04 |
| 5 | Pass | TCP | SERVEURS net | any | 443 | non | SERVEURS vers Internet MAJ | 2026-09-05 19:24:21 |

Preuve (état du 5 sept., avant la règle DNS) : [`screenshots/26-regles-serveurs.png`](../screenshots/26-regles-serveurs.png).

> Le nombre `1788634015` visible dans les journaux `filterlog` (champ « tracker ») est l'identifiant de règle : c'est aussi son horodatage Unix de création. Il permet de relier une ligne de journal à la règle exacte, par exemple `1788634015` = « Bloc LAN vers DMZ ».

## Analyse

**[RÉEL]**

- **A1 – Refus implicite non journalisé explicitement** : seule la DMZ possède une règle finale « bloc tout ». LAN et SERVEURS s'appuient sur le refus implicite de pfSense. Les journaux montrent que ce refus est tout de même tracé sous l'identifiant de règle `1000000103` (par exemple LAN 10.10.10.100 → 8.8.8.8:53, [`screenshots/64-…`](../screenshots/64-journalisation-blocage-lan-vers-dmz.png)).
- **A2 – Règles DNS ajoutées après coup** : les règles « vers DNS pfSense » du LAN et de SERVEURS datent du 6 septembre, plusieurs heures après les règles initiales. Les journaux montrent des tentatives DNS vers 8.8.8.8 et 1.1.1.1 bloquées (poste LAN 10.10.10.100 ; `srv-web` en DMZ). La DMZ n'a aucune règle DNS : le serveur web ne peut résoudre aucun nom.
- **A3 – Le DHCP du LAN diffuse 8.8.8.8 et 1.1.1.1 comme serveurs DNS**, alors que la politique n'autorise le DNS que vers pfSense : un client qui applique ces valeurs voit ses requêtes bloquées.
- **A4 – « LAN vers Internet Web » a pour destination `any`** : la règle couvre aussi les réseaux internes non bloqués plus haut, c'est-à-dire ici SERVEURS (80/443). Seule la DMZ est explicitement exclue avant.
- **A5 – Règle anti-blocage** : elle autorise **tout le LAN** vers pfSense sur 80 (interface web, en HTTP) et 22 (SSH). L'alias `Postes_Admin` ne restreint donc pas l'administration de pfSense elle-même.
- **A6 – `Postes_Admin` (10.10.10.100) est dans la plage DHCP** 10.10.10.100 – 10.10.10.200 : l'adresse n'est garantie que si le poste est en IP fixe ou réservée **[À CONFIRMER]**.
- **A7 – Alias `Admin_Ports` défini mais non utilisé** : les règles admin utilisent directement les ports 445 et 3389.
- **A8 – Les règles DMZ « Any vers Web DMZ » filtrent le trafic entrant par l'interface DMZ** (initié depuis la DMZ). Le trafic publié depuis Internet est autorisé par les règles WAN issues de la redirection. Ces deux règles affichent 0 état sur la capture.

**[RECOMMANDATION]**

- Remplacer la destination `any` des règles Web par un alias « tout sauf RFC1918 » (A4).
- Publier 10.10.10.1 comme DNS dans le DHCP du LAN (A3).
- Supprimer la règle anti-blocage (option de l'interface web, réglages avancés) et la remplacer par une règle limitée à `Postes_Admin` en HTTPS (A5).
- Ajouter une règle finale journalisée sur LAN et SERVEURS pour homogénéiser (A1), ou documenter que le refus implicite fait foi.
- Réserver l'adresse de `Postes_Admin` par un mappage DHCP statique (A6).
