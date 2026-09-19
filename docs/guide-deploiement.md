# Guide de déploiement (de A à Z)

Ce guide permet de **reproduire la maquette** : pfSense en coupure, VLAN LAN / SERVEURS / DMZ, Suricata, journalisation centralisée.

**À lire avant de commencer**

- Les **valeurs** (adresses, ports, règles, paramètres Suricata) sont celles de la maquette réelle **[RÉEL]**, tirées de l'export de configuration et des captures.
- Les **chemins de menu, commandes de vérification et fichiers de configuration Linux** sont ceux de pfSense/Linux standards, rédigés à partir de la configuration finale. Ce guide n'a **pas été rejoué à blanc** sur un environnement neuf: valider les étapes lors d'un premier déploiement et corriger le guide si besoin.
- Étiquettes : **[RECOMMANDATION]** pratique conseillée, différente ou en plus de la maquette ·
- Les commandes d'attaque et de scan ne s'exécutent que dans la maquette.

## Sommaire

0. [Prérequis](#0-prérequis)
1. [Paramètres à adapter](#1-paramètres-à-adapter)
2. [Étape 1 : plateforme et topologie](#2-étape-1--plateforme-et-topologie)
3. [Étape 2 : switch SW1](#3-étape-2--switch-sw1)
4. [Étape 3 : installation de pfSense](#4-étape-3--installation-de-pfsense)
5. [Étape 4 : VLAN, interfaces, DHCP](#5-étape-4--vlan-interfaces-dhcp)
6. [Étape 5 : alias](#6-étape-5--alias)
7. [Étape 6 : règles de filtrage](#7-étape-6--règles-de-filtrage)
8. [Étape 7 : redirection de ports (NAT)](#8-étape-7--redirection-de-ports-nat)
9. [Étape 8 : serveur web en DMZ](#9-étape-8--serveur-web-en-dmz)
10. [Étape 9 : serveur Syslog et journalisation distante](#10-étape-9--serveur-syslog-et-journalisation-distante)
11. [Étape 10 : Suricata](#11-étape-10--suricata)
12. [Étape 11 : recette et tests](#12-étape-11--recette-et-tests)
13. [Dépannage](#13-dépannage)
14. [Étape 12 : sauvegarde et assainissement](#14-étape-12--sauvegarde-et-assainissement)

---

## 0. Prérequis

### Matériel / ressources

| Élément | Valeur |
|---|---|
| VM pfSense | 2 vCPU, 4 Go de RAM, disque 16 Go, **2 cartes réseau virtio** (`vtnet0` = WAN, `vtnet1` = trunk) |
| Switch managé (SW1) | 4 ports utilisés : 1 trunk (Gi0/0) + 3 accès (Gi0/1 à Gi0/3) |
| VM `srv-web` | Ubuntu ubuntu serveur, 1 carte réseau |
| VM `srv-syslog` | Linux ubuntu serveur, 1 carte réseau |
| Poste d'administration | 1 machine dans le VLAN 10 (`10.10.10.100`) |
| Poste de test | Kali Linux dans le VLAN 10 (`10.10.10.101`) |
| Plateforme | Émulation réseau permettant VLAN/trunk (EVE-NG probable, [À CONFIRMER]) |

### Logiciels

| Logiciel | Version  | Source |
|---|---|---|
| pfSense CE | 2.8.1 | Page de téléchargement Netgate (installateur Netgate) |
| Suricata (paquet pfSense) | 7.0.2 | Gestionnaire de paquets pfSense |
| Règles ET Open | dernière disponible | Téléchargées par le paquet Suricata |
| nginx | 1.18.0 | Dépôts Ubuntu |
| Nmap / Hydra | 7.99 / v9.6 | Kali Linux |

### Réseau

- Un accès Internet côté WAN : installation de Suricata et téléchargement des règles. Dans la maquette, le WAN est un réseau 192.168.100.0/24 avec passerelle 192.168.100.2 et DHCP.
- Le WAN de la maquette est une plage **privée**. Dans ce cas, **ne pas activer « Bloquer les réseaux privés »** sur le WAN (l'option n'est pas activée dans la maquette). Le blocage des bogons est activé **[RÉEL]**. **[RECOMMANDATION]** : activer le blocage des réseaux privés sur un WAN public.

### Comptes et droits

| Compte | Usage | Droits |
|---|---|---|
| Administrateur de la plateforme de virtualisation | Créer les nœuds, les liens, les VLAN de câblage | Administration de la plateforme |
| `admin` pfSense | Toute la configuration | Groupe `admins` (accès complet) ; **changer le mot de passe par défaut dès la première connexion** |
| Compte sudo sur `srv-web` et `srv-syslog` | Installation de paquets, fichiers `/etc` | `sudo` |
| Accès console du switch | Configuration SW1 | Mode privilégié  |
| Poste de test | Scans | Droits de lancer Nmap et Hydra |

### Compétences supposées

VLAN et trunk 802.1Q, adressage IPv4, filtrage stateful, NAT, Linux en ligne de commande, lecture de journaux.

---

## 1. Paramètres à adapter

Remplacer ces valeurs si votre environnement diffère. Toutes les autres sections utilisent les valeurs de la maquette.

| Paramètre | Valeur maquette [RÉEL] | Où l'adapter |
|---|---|---|
| Réseau WAN, passerelle | 192.168.100.0/24, 192.168.100.2 (DHCP) | Fourni par la plateforme ; pfSense l'obtient en DHCP |
| Noms des interfaces pfSense | `vtnet0` (WAN), `vtnet1` (trunk) | Étape 3 ; d'autres hyperviseurs donnent `em0`, `igb0`, `vmx0` |
| VLAN | 10 (LAN), 20 (SERVEURS), 30 (DMZ) | Étapes 2 et 4 |
| Réseaux internes | 10.10.10.0/24, 10.10.20.0/24, 10.10.30.0/24 | Étapes 4 à 7 |
| Poste d'administration | 10.10.10.100 | Alias `Postes_Admin` |
| Serveur web | 10.10.30.6 | Alias `Serveur_Web_DMZ`, netplan de `srv-web` |
| Serveur Syslog | 10.10.20.5 | Alias `Serveur_Syslog`, journalisation distante |
| Plage DHCP LAN | 10.10.10.100 – 10.10.10.200 | Étape 4 |
| Planification des mises à jour de règles | tous les 7 jours à 03:00 | Étape 10 |

---

## 2. Étape 1 : plateforme et topologie

**Objectif** : créer les nœuds et le câblage.

Câblage **[RÉEL]** (schéma [`../diagrams/architecture-cible.png`](../diagrams/architecture-cible.png)) :

| Lien | Extrémité A | Extrémité B |
|---|---|---|
| WAN | Nœud « Internet » (accès externe de la plateforme) | pfSense `e0` = `vtnet0` |
| Trunk | pfSense `e1` = `vtnet1` | SW1 `Gi0/0` |
| LAN | SW1 `Gi0/1` | Poste(s) du VLAN 10 |
| SERVEURS | SW1 `Gi0/2` | `srv-syslog` |
| DMZ | SW1 `Gi0/3` | `srv-web` |


**Vérification** : tous les nœuds démarrent ; les liens sont actifs côté plateforme.

**Erreurs possibles** : cartes réseau non virtio (les noms `vtnet` changent), pfSense sans accès Internet côté WAN (Suricata ne pourra pas télécharger ses règles).

---

## 3. Étape 2 : switch SW1

**Objectif** : créer les VLAN, le trunk et les ports d'accès. Détail et sorties `show` : [`../config/sw1-switch.md`](../config/sw1-switch.md).

Commandes **reconstituées** (à adapter au modèle) **[RECOMMANDATION]** :

```text
configure terminal
 vlan 10
  name LAN
 vlan 20
  name SERVEURS
 vlan 30
  name DMZ
 exit
interface GigabitEthernet0/0
 switchport trunk encapsulation dot1q
 switchport mode trunk
 switchport trunk allowed vlan 10,20,30
interface GigabitEthernet0/1
 switchport mode access
 switchport access vlan 10
interface GigabitEthernet0/2
 switchport mode access
 switchport access vlan 20
interface GigabitEthernet0/3
 switchport mode access
 switchport access vlan 30
end
write memory
```

**Vérification** (résultat attendu **[RÉEL]**, `screenshots/20-…`) :

```text
SW1# show vlan brief          → VLAN 10 LAN (Gi0/1), 20 SERVEURS (Gi0/2), 30 DMZ (Gi0/3)
SW1# show interfaces trunk    → Gi0/0 on 802.1q trunking, VLANs 10,20,30 autorisés
```

**Erreurs possibles** : VLAN absents de la base (`vlan 10` non créé) ; `switchport trunk encapsulation dot1q` refusé sur les modèles qui ne supportent que le dot1q (l'omettre) ; port d'accès laissé en VLAN 1.

---

## 4. Étape 3 : installation de pfSense

**Objectif** : installer pfSense CE 2.8.1 sur la VM.

1. Télécharger l'installateur pfSense CE 2.8.1 depuis le site de Netgate (`screenshots/00-…`) et le monter sur la VM.
2. Installer avec le système de fichiers **ZFS** sur le disque de 16 Go **[RÉEL]**.
3. Après redémarrage, à la console : **affecter** `vtnet0` au **WAN** et `vtnet1` au **LAN** (adresse initiale du LAN de la maquette : `192.168.1.1/24`, `pfsense-baseline-…xml`).
4. Depuis un poste du LAN initial, ouvrir l'interface web, **changer le mot de passe `admin`**.
5. Régler : nom d'hôte `pfSense`, domaine `home.arpa`, fuseau `Etc/UTC`, serveur NTP `2.pfsense.pool.ntp.org`, langue française **[RÉEL]**.
6. **[RECOMMANDATION]** Activer HTTPS pour l'interface web. La maquette utilise HTTP et SSH activé (voir [`rapport-technique.md`](rapport-technique.md#102-faiblesses-connues-à-corriger-avant-toute-réutilisation)).

**Vérification** : le tableau de bord montre 2 CPU, environ 4 Go de RAM, disque ZFS de 16 Go et une adresse WAN obtenue en DHCP (`192.168.100.14` dans la maquette, `screenshots/28-…`).

**Erreurs possibles** : pas d'adresse WAN (câblage ou DHCP de la plateforme) ; échec de l'installateur si le disque est trop petit.

---

## 5. Étape 4 : VLAN, interfaces, DHCP

**Objectif** : créer les VLAN 10/20/30 sur `vtnet1` et affecter les interfaces.

> **Attention** : déplacer le LAN de `vtnet1` vers `vtnet1.10` coupe l'accès au LAN initial. Travailler **depuis la console** de pfSense, ou depuis un poste déjà dans le VLAN 10 une fois SW1 configuré.

1. **Interfaces > Assignments > VLANs** : créer trois VLAN sur `vtnet1` avec les balises 10 (description `LAN`), 20 (`SERVEURS`), 30 (`DMZ`) **[RÉEL]** (`screenshots/21-…`).
2. **Interfaces > Assignments** :
   - `LAN` → `vtnet1.10`
   - `OPT1` renommée `DMZ` → `vtnet1.30`
   - `OPT2` renommée `SERVEURS` → `vtnet1.20`
3. Activer chaque interface, **IPv4 statique** :

| Interface | Adresse |
|---|---|
| LAN | 10.10.10.1/24 |
| SERVEURS | 10.10.20.1/24 |
| DMZ | 10.10.30.1/24 |
| WAN | DHCP, **bloquer les bogons** activé |

4. **Services > DHCP Server > LAN** : activer, plage `10.10.10.100` à `10.10.10.200`. Aucun DHCP sur SERVEURS ni DMZ (adresses statiques).
   - Serveurs DNS diffusés dans la maquette : `8.8.8.8` et `1.1.1.1` **[RÉEL]**.
   - **[RECOMMANDATION]** : diffuser `10.10.10.1` à la place. La politique de filtrage n'autorise le DNS que vers pfSense ; avec 8.8.8.8 / 1.1.1.1 les requêtes des clients sont bloquées (constaté, `tests/logs/extraits-journaux.md` § 4).
5. **Services > DNS Resolver** : activé (Unbound). **[RECOMMANDATION]** : limiter les interfaces d'écoute à LAN et SERVEURS (`active_interface` est vide dans la maquette).
6. **[RECOMMANDATION]** Réserver `10.10.10.100` (poste d'administration) par un mappage DHCP statique : l'adresse est dans la plage dynamique.

**Vérification** [RÉEL, `screenshots/22-…`] : **Statut > Interfaces** affiche `up` et les adresses 192.168.100.14 (WAN), 10.10.10.1, 10.10.20.1 et 10.10.30.1, sans erreur. Depuis un poste du VLAN 10 : adresse en 10.10.10.100 – .200 et `ping 10.10.10.1` répond.

**Erreurs possibles** : pas de DHCP sur le LAN (port du poste hors VLAN 10, trunk absent) ; VLAN créés sur la mauvaise interface parente ; perte d'accès web (voir Dépannage).

---

## 6. Étape 5 : alias

**Firewall > Aliases** : créer **[RÉEL]** (`screenshots/23-…`) :

| Nom | Type | Valeur | Description |
|---|---|---|---|
| `Postes_Admin` | Hôte | 10.10.10.100 | postes autorisés à administrer pfSense |
| `Serveur_Web_DMZ` | Hôte | 10.10.30.6 | serveur Web en DMZ |
| `Serveur_Syslog` | Hôte | 10.10.20.5 | serveur de centralisation des journaux |
| `Admin_Ports` | Ports | 445 3389 | (défini dans la maquette, non utilisé par les règles) |

**Vérification** : les quatre alias apparaissent dans la liste.

---

## 7. Étape 6 : règles de filtrage

**Objectif** : appliquer la politique. Référence complète, dans l'ordre : [`../config/regles-pare-feu.md`](../config/regles-pare-feu.md).

**Principe** : l'ordre compte (première correspondance gagnante), le refus est implicite. Pour chaque règle : **Firewall > Rules > *interface* > Add**. Cocher « Log packets that are handled by this rule » pour les règles **Block**. « (self) » = *This firewall (self)*.

### LAN

| # | Action | Proto | Source | Destination | Port | Log | Description |
|---|---|---|---|---|---|---|---|
| 1 | Pass | TCP/UDP | LAN subnets | This firewall (self) | 53 | non | LAN vers DNS pfSense |
| 2 | Block | Any | LAN subnets | 10.10.30.0/24 | any | **oui** | Bloc LAN vers DMZ |
| 3 | Pass | TCP | `Postes_Admin` | 10.10.20.0/24 | 445 | non | Admin SERVEURS RDP/SMB |
| 4 | Pass | TCP | `Postes_Admin` | 10.10.20.0/24 | 3389 | non | Admin SERVEURS RDP/SMB |
| 5 | Pass | TCP | LAN subnets | any | 80 | non | LAN vers Internet Web |
| 6 | Pass | TCP | LAN subnets | any | 443 | non | LAN vers Internet Web |
| 7 | Pass | TCP/UDP | LAN subnets | `Serveur_Syslog` | 514 | non | LAN vers Syslog |

La règle anti-blocage (80 et 22 vers l'adresse LAN) est présente par défaut **[RÉEL]**. **[RECOMMANDATION]** : la désactiver et la remplacer par une règle limitée à `Postes_Admin`.

### DMZ

| # | Action | Proto | Source | Destination | Port | Log | Description |
|---|---|---|---|---|---|---|---|
| 1 | Pass | TCP | any | `Serveur_Web_DMZ` | 80 | non | Any vers Web DMZ |
| 2 | Pass | TCP | any | `Serveur_Web_DMZ` | 443 | non | Any vers Web DMZ |
| 3 | Pass | TCP/UDP | `Serveur_Web_DMZ` | `Serveur_Syslog` | 514 | non | Web DMZ vers Syslog |
| 4 | Block | Any | DMZ subnets | 10.10.10.0/24 | any | **oui** | Bloc DMZ vers LAN |
| 5 | Block | Any | DMZ subnets | 10.10.20.0/24 | any | **oui** | Bloc DMZ vers SERVEURS |
| 6 | Block | Any | DMZ subnets | any | any | **oui** | Bloc DMZ vers any (finale) |

### SERVEURS

| # | Action | Proto | Source | Destination | Port | Log | Description |
|---|---|---|---|---|---|---|---|
| 1 | Pass | TCP/UDP | SERVEURS subnets | This firewall (self) | 53 | non | SERVEURS vers DNS pfSense |
| 2 | Block | Any | SERVEURS subnets | 10.10.10.0/24 | any | **oui** | Bloc SERVEURS vers LAN |
| 3 | Block | Any | SERVEURS subnets | 10.10.30.0/24 | any | **oui** | Bloc SERVEURS vers DMZ |
| 4 | Pass | TCP | SERVEURS subnets | any | 80 | non | SERVEURS vers Internet MAJ |
| 5 | Pass | TCP | SERVEURS subnets | any | 443 | non | SERVEURS vers Internet MAJ |

### WAN

Aucune règle manuelle : les deux règles `Any → Serveur_Web_DMZ` (80 et 443) sont générées avec la redirection de l'étape 7.

**[RECOMMANDATION]** : remplacer la destination `any` des règles Web (LAN 5 et 6, SERVEURS 4 et 5) par un alias « tout sauf RFC1918 » ; ajouter les règles DNS pour la DMZ **uniquement** si le serveur web doit résoudre des noms.

**Vérification** :

```bash
# depuis un poste du VLAN 10 (LAN) :
curl --max-time 10 http://10.10.30.6     # attendu : délai dépassé
ping -c 4 10.10.30.6                     # attendu : aucune réponse
```

Puis **Status > System Logs > Firewall** : lignes `block` de la règle « Bloc LAN vers DMZ ». Attendu **[RÉEL]** : `screenshots/60-…`, `64-…`.

**Erreurs possibles** : règle Pass placée au-dessus d'une règle Block (le blocage ne s'applique plus) ; « Block » sans journal (pas de trace) ; alias mal orthographié ; règle DNS oubliée (résolution impossible, voir Dépannage).

---

## 8. Étape 7 : redirection de ports (NAT)

**Firewall > NAT > Port Forward > Add** deux fois **[RÉEL]** (`screenshots/27-…`) :

| Interface | Proto | Source | Destination | Port destination | IP de redirection | Port redirigé | Description | Règle de filtrage |
|---|---|---|---|---|---|---|---|---|
| WAN | TCP | any | WAN address | 80 | `Serveur_Web_DMZ` | 80 | NAT-WEB-DMZ-80 | Créer la règle associée |
| WAN | TCP | any | WAN address | 443 | `Serveur_Web_DMZ` | 443 | NAT-WEB-DMZ-443 | Créer la règle associée |

Réflexion NAT désactivée (`disablenatreflection = yes`). NAT sortant : mode automatique par défaut **[À CONFIRMER]**.

**Vérification** (depuis une machine du côté WAN) :

```bash
curl -I http://192.168.100.14
# attendu : en-têtes nginx (Server: nginx/1.18.0 (Ubuntu))
nmap -sV -Pn -p 53,80,443 192.168.100.14
```

Dans la maquette (scan `-sV`, `screenshots/63-…`), le port 80 répond nginx 1.18.0 et **443 est fermé** : le serveur ne sert que le port 80. Le port 53 (Unbound) répond aussi (voir recommandation de l'étape 4).

**Erreurs possibles** : règle de filtrage associée absente ; serveur web injoignable (passerelle du serveur incorrecte) ; test réalisé depuis le LAN alors que la réflexion NAT est désactivée.

---

## 9. Étape 8 : serveur web en DMZ

**Objectif** : `srv-web` (10.10.30.6) sert une page sur le port 80.

> **Ordre important [RECOMMANDATION]** : la DMZ n'a **aucune sortie vers Internet ni DNS** (règle finale « Bloc DMZ vers any »). `apt` ne fonctionnera donc pas une fois les règles appliquées. Installer nginx **avant** l'étape 6, ou connecter temporairement le serveur au VLAN 20 (qui autorise 80/443 et DNS), ou utiliser un dépôt local.

1. Adressage statique, exemple netplan (nom d'interface à adapter) **[RECOMMANDATION]** :

```yaml
# /etc/netplan/50-dmz.yaml
network:
  version: 2
  ethernets:
    ens3:                      # à adapter
      dhcp4: false
      addresses: [10.10.30.6/24]
      routes:
        - to: default
          via: 10.10.30.1
```

```bash
sudo netplan apply
sudo apt update && sudo apt install -y nginx
sudo systemctl enable --now nginx
```

2. La page servie est celle par défaut de nginx.

**Vérification** : sur `srv-web`, `curl -I http://localhost` renvoie `200 OK` ; depuis un hôte du WAN, `curl -I http://192.168.100.14` traverse la redirection (étape 7).

**Erreurs possibles** : mauvaise passerelle (10.10.30.1 attendue) ; serveur resté en DHCP ; nginx non installé faute de sortie Internet.

---

## 10. Étape 9 : serveur Syslog et journalisation distante

### 10.1 Sur `srv-syslog` (10.10.20.5)

Configuration recommandée (non fournie dans les preuves, reproduit la répartition constatée) : voir [`../config/syslog-serveur.md`](../config/syslog-serveur.md).

```conf
# /etc/rsyslog.d/10-pfsense.conf
module(load="imudp")
input(type="imudp" port="514")
module(load="imtcp")
input(type="imtcp" port="514")
if $programname == 'filterlog' then /var/log/firewall.log
& stop
if $programname == 'suricata' then /var/log/suricata-eve.log
& stop
```

```bash
sudo systemctl restart rsyslog
sudo ss -lunp | grep ':514'      # attendu : rsyslogd à l'écoute
```

Adresse statique 10.10.20.5/24, passerelle 10.10.20.1.

### 10.2 Sur pfSense

**Status > System Logs > Settings > Remote Logging Options** **[RÉEL]** (`screenshots/50-…`) :

| Paramètre | Valeur |
|---|---|
| Send log messages to remote syslog server | coché |
| Source Address | interface **SERVEURS** |
| IP Protocol | IPv4 |
| Remote log servers | `10.10.20.5:514` |
| Remote Syslog Contents | **System Events** et **Firewall Events** uniquement |

**Vérification** : provoquer un blocage (étape 6), puis sur `srv-syslog` :

```bash
sudo tail -f /var/log/firewall.log
# attendu : lignes 'filterlog[...]: ...,block,in,...' avec l'IP source du test
```

**Erreurs possibles** : `rsyslog` n'écoute pas le port 514 ; pare-feu local du serveur bloquant 514 ; source d'émission mal choisie ; UDP par défaut (perte possible, non réessayé).

---

## 11. Étape 10 : Suricata

Référence des paramètres : [`../config/suricata.md`](../config/suricata.md).

### 11.1 Installation [RÉEL]

**System > Package Manager > Available Packages** : rechercher `suricata` > **Install** (`screenshots/40-…` à `42-…`). Attendre « installé avec succès » (13 paquets, environ 57 Mo).

### 11.2 Paramètres globaux [RÉEL]

**Services > Suricata > Global Settings** :

| Paramètre | Valeur |
|---|---|
| Install ET Open rules | **Coché** (ET Pro, Snort, Feodo, ABUSE.ch : décochés) |
| Update interval | 7 jours |
| Update start time | 03:00 |
| Live rule swap on update | coché |
| Remove blocked hosts interval | Never |
| Keep settings on package removal | coché |

**Services > Suricata > Updates** : cliquer **Update** ; le journal doit se terminer par un succès (`screenshots/43-…`). Le paquet est livré sans règles.

### 11.3 Instances

**Services > Suricata > Interfaces > Add**, une instance par interface **[RÉEL]** :

| Réglage | WAN | DMZ | LAN |
|---|---|---|---|
| Interface | WAN | DMZ | LAN |
| Enable | oui | oui | oui |
| Runmode | workers | workers | autofp |
| **Block Offenders** | **oui** | **oui** | non |
| IPS Mode | **Legacy Mode** | **Legacy Mode** | Legacy (blocage désactivé) |
| Which IP to block | Both | Both | – |
| Kill states | oui | oui | oui |
| Pass list / Home list | default | default | default |
| Send alerts to system log | non | non | **oui** (`local1`, `notice`) |
| EVE JSON log | non | non | **oui** |
| Detect-engine profile | Medium | Medium | Medium |

**Catégories de règles** (identiques sur les trois instances, 26 fichiers) : `emerging-scan`, `emerging-attack_response`, `emerging-web_server`, `emerging-web_specific_apps` et les fichiers d'événements de protocole (`app-layer-events`, `decoder-events`, `stream-events`, `files`, `http-events`, `http2-events`, `tls-events`, `dns-events`, `dhcp-events`, `ftp-events`, `smtp-events`, `ssh-events`, `smb-events`, `nfs-events`, `ntp-events`, `ipsec-events`, `kerberos-events`, `quic-events`, `rfb-events`, `mqtt-events`, `modbus-events`, `dnp3-events`).

**Démarrer** chaque instance (icône verte « Suricata Status »). Preuve : `screenshots/45-…`.

**Mode Inline IPS** : la maquette l'a essayé (`screenshots/44-…`, 6 septembre) puis est passée au Legacy Mode. La cause n'est pas documentée. Dans un déploiement neuf, tester l'Inline IPS ; si l'instance ne démarre pas ou le trafic est perturbé sur des cartes virtio/VLAN, revenir au Legacy Mode.

**[RECOMMANDATION]** : activer « Send alerts to system log » aussi sur WAN et DMZ, sinon leurs alertes n'arrivent pas sur `srv-syslog`.

**Vérification** :

1. **Services > Suricata > Interfaces** : trois pastilles vertes ; colonne « Blocking Mode » = Legacy / Legacy / Disabled.
2. Depuis le poste de test : `nmap -sV -Pn -p1-1000 192.168.100.14`.
3. **Services > Suricata > Alerts** (instance DMZ) : alertes `ET SCAN Possible Nmap User-Agent Observed` (`screenshots/62-…`).
4. Sur `srv-syslog` : `sudo tail -f /var/log/suricata-eve.log` (attendu : ligne `[1:2024364:4] ET SCAN Possible Nmap User-Agent Observed …`).

**Erreurs possibles** : règles non téléchargées (pas d'Internet côté WAN, DNS de pfSense) ; instance qui ne démarre pas (interface non `up`, mémoire insuffisante) ; aucune alerte (catégories `emerging-scan` non cochées ou instance arrêtée) ; alerte absente du serveur (envoi vers syslog non activé sur l'instance concernée).

---

## 12. Étape 11 : recette et tests

Exécuter la campagne : [`../tests/plan-de-tests.md`](../tests/plan-de-tests.md) et les scripts de [`../scripts/`](../scripts/). Résultats de référence **[RÉEL]** :

| Test | Commande | Attendu |
|---|---|---|
| LAN → DMZ HTTP | `curl --max-time 10 http://10.10.30.6` | Aucune réponse |
| LAN → DMZ ICMP | `ping -c 4 10.10.30.6` | Aucune réponse ; blocage dans `firewall.log` |
| DMZ → LAN ICMP | `ping -c 4 10.10.10.101` depuis `srv-web` | Aucune réponse ; blocage dans `firewall.log` |
| Scan WAN | `nmap -sV -Pn -p1-1000 192.168.100.14` | 53 et 80 ouverts (nginx 1.18.0), 443 fermé |
| Détection | idem | Alerte SID 2024364 dans Suricata et sur `srv-syslog` |
| Temps HTTP | `scripts/mesure-latence-http.sh http://192.168.100.14` | ≈ 13 ms sans Suricata (12 à 17 ms) |

**À ajouter pour une recette complète** (absent des preuves, partie D du plan de tests) : force brute Hydra après déploiement, test de blocage par Suricata avec une source hors liste de passage, mesures de charge avec Suricata actif.

---

## 13. Dépannage

Colonne « Origine » : **[OBSERVÉ]** vu dans la maquette ; **[COURANT]** problème classique de ce type d'architecture, non observé dans les preuves.

| Symptôme | Origine | Cause probable | Solution |
|---|---|---|---|
| Requêtes DNS vers 8.8.8.8 / 1.1.1.1 bloquées (journaux `block`, règle `1000000103` ou finale DMZ) | OBSERVÉ | La politique n'autorise le DNS que vers pfSense ; le DHCP diffuse 8.8.8.8 / 1.1.1.1 | DNS du DHCP = 10.10.10.1 ; règle « vers DNS pfSense » sur LAN et SERVEURS |
| `apt` ne fonctionne pas sur `srv-web` | OBSERVÉ (conséquence des règles) | DMZ sans sortie Internet ni DNS | Installer avant les règles, ou passer temporairement en VLAN 20 |
| `ping 10.10.30.6` du LAN sans réponse | OBSERVÉ | Comportement voulu (règle « Bloc LAN vers DMZ ») | Aucune action ; voir la trace dans `firewall.log` |
| Suricata : instance en Inline IPS non retenue | OBSERVÉ | Mode Inline abandonné au profit du Legacy Mode (cause à documenter) | Legacy Mode |
| Alertes WAN/DMZ absentes de `srv-syslog` | OBSERVÉ (configuration) | Envoi vers syslog activé uniquement sur l'instance LAN | Activer l'envoi sur WAN et DMZ |
| Scan complet extrêmement long (≈ 12 min) | OBSERVÉ | Presque tous les ports sont filtrés ; scripts NSE | Limiter la plage de ports pour les tests répétés |
| Port 53 ouvert sur l'adresse WAN | OBSERVÉ | Unbound écoute sans restriction d'interface | Limiter les interfaces d'écoute d'Unbound ; retester depuis un vrai côté WAN |
| Serveur web ne répond pas en HTTPS | OBSERVÉ | nginx n'écoute pas sur 443 (`443/tcp closed`) | Configurer un certificat et l'écoute 443 |
| Perte d'accès à l'interface web après la création des VLAN | COURANT | LAN déplacé sur `vtnet1.10` | Console pfSense (menu d'affectation des interfaces / adresse IP) ; poste dans le VLAN 10 |
| Aucun DHCP sur le LAN | COURANT | Port du poste hors VLAN 10, trunk mal configuré, DHCP non activé | `show vlan brief`, `show interfaces trunk` ; activer le service DHCP |
| Aucun trafic entre pfSense et les VLAN | COURANT | VLAN non autorisés sur le trunk, encapsulation ou VLAN native différentes | Vérifier `switchport trunk allowed vlan 10,20,30` |
| `srv-syslog` ne reçoit rien | COURANT | `rsyslog` non à l'écoute, pare-feu local, mauvaise source | `ss -lunp`, autoriser UDP/TCP 514, vérifier l'adresse source |
| Règles Suricata non téléchargées | COURANT | Pas d'Internet ou de DNS côté pfSense | Vérifier la passerelle WAN, utiliser « Force » dans l'onglet Updates |

---

## 14. Étape 12 : sauvegarde et assainissement

1. **Diagnostics > Backup & Restore** : télécharger `config.xml`.
2. **Ne jamais publier ce fichier tel quel** : il contient le hash du mot de passe administrateur, la clé privée du certificat de l'interface web et les clés d'hôte SSH.
3. Générer une version publiable :

```bash
python3 scripts/sanitize-pfsense-config.py config.xml config/pfsense-config-assainie.xml
grep -n -E "<(bcrypt-hash|crt|prv|xmldata)>" config/pfsense-config-assainie.xml   # tout doit valoir REDACTED
```

4. Relire le fichier assaini avant `git add`. Il sert de documentation ; il n'est pas importable tel quel (certificat et clés supprimés).
5. Conserver l'export brut **hors du dépôt** (chiffré) : `.gitignore` bloque `config.xml` et les fichiers `*-raw.xml`.

**Vérification finale** : `git status` ne liste aucun fichier `config.xml` ; la recherche `grep -rn -E 'BEGIN [A-Z ]*(PRIVATE KEY|CERTIFICATE)' .` ne retourne rien.
