# Rapport technique : segmentation VLAN/DMZ avec pfSense et détection d'intrusion avec Suricata

| | |
|---|---|
| **Projet** | Sécurisation périmétrique d'une maquette réseau : pare-feu pfSense en coupure, segmentation LAN / SERVEURS / DMZ, IDS/IPS Suricata, journalisation centralisée |
| **Cadre** | Dossier de projets tutorés « Administration avancée et sécurisation des réseaux et systèmes » (RNCP39781-PEP-CM02), mission n°08, pour AfriNova Digital |
| **Auteur** | DIABY Aboubacar Sidik |
| **Période des preuves** | 4 au 7 septembre 2026 (horodatages des captures et des règles) |
| **Environnement** | Maquette virtualisée, réseau privé isolé, aucune donnée réelle |


## Sommaire

1. [Contexte et problématique](#1-contexte-et-problématique)
2. [Objectifs](#2-objectifs)
3. [Architecture et fonctionnement](#3-architecture-et-fonctionnement)
4. [Technologies, outils et versions](#4-technologies-outils-et-versions)
5. [Prérequis matériels et logiciels](#5-prérequis-matériels-et-logiciels)
6. [Étapes de conception et de mise en œuvre](#6-étapes-de-conception-et-de-mise-en-œuvre)
7. [Configuration détaillée](#7-configuration-détaillée)
8. [Tests réalisés et résultats](#8-tests-réalisés-et-résultats)
9. [Problèmes rencontrés et solutions](#9-problèmes-rencontrés-et-solutions)
10. [Mesures de sécurité mises en place](#10-mesures-de-sécurité-mises-en-place)
11. [Limites actuelles](#11-limites-actuelles)
12. [Améliorations et évolutions possibles](#12-améliorations-et-évolutions-possibles)
13. [Conclusion](#13-conclusion)
14. [Annexes](#14-annexes)

---

## 1. Contexte et problématique

**Contexte [RÉEL]** : le point de départ est une maquette de réseau **à plat** (figure ci-dessous) : un routeur d'accès au filtrage minimal (NAT, blocage des connexions entrantes non sollicitées) relie Internet à un switch non managé, sur lequel sont raccordés sans distinction les postes utilisateurs, un serveur interne (applicatif, fichiers) et un serveur web destiné à être exposé.

![Architecture existante](../diagrams/architecture-existante.png)

**Problématique** : trois faiblesses de l'existant, exposées dans le rapport d'origine :

1. Aucune segmentation : un poste compromis atteint directement les serveurs internes, et l'exposition d'un service met en jeu tout le réseau.
2. Filtrage trop permissif : flux sortants autorisés par défaut, pas de règles explicites par usage.
3. Aucune détection d'intrusion, journalisation dispersée et sans corrélation.

**Constat mesuré sur la référence [RÉEL]** : sur le réseau à plat, un `nmap -sS -p1-1000` découvre les ports 22 (ssh) et 80 (http) d'une machine, et une attaque par dictionnaire SSH avec Hydra retrouve un mot de passe valide en 3 secondes (tests A1 et A2, [`tests/plan-de-tests.md`](../tests/plan-de-tests.md)).

**Question posée** : comment isoler les usages, n'exposer qu'un service en DMZ, détecter les comportements hostiles et conserver des traces exploitables, avec des outils libres et une charge maîtrisée ?

## 2. Objectifs

| # | Objectif | Statut |
|---|---|---|
| O1 | Déployer pfSense en coupure entre Internet et le réseau interne | **[RÉEL]** : WAN `vtnet0`, trunk `vtnet1` |
| O2 | Segmenter en trois zones (LAN, SERVEURS, DMZ) au moindre privilège | **[RÉEL]** : VLAN 10 / 20 / 30, 20 règles |
| O3 | Publier un service web depuis la DMZ uniquement | **[RÉEL]** : redirection 80/443 vers 10.10.30.6 |
| O4 | Détecter scans et comportements hostiles avec Suricata | **[RÉEL]** en détection : alerte SID 2024364 démontrée |
| O5 | Bloquer automatiquement les sources hostiles (IPS) | **Configuré** (mode Legacy, WAN et DMZ) ; **effet non démontré** par les preuves |
| O6 | Centraliser les journaux pare-feu et IDS/IPS | **[RÉEL]** : `srv-syslog` reçoit `filterlog` et alertes Suricata |
| O7 | Valider par des tests reproductibles | **[RÉEL]** en partie (parties A à C du plan de tests) ; parties manquantes listées en partie D |
| O8 | Maîtriser l'impact sur les performances | **Non démontré** avec Suricata actif : mesures disponibles avant Suricata uniquement |

## 3. Architecture et fonctionnement

Voir [`architecture.md`](architecture.md) pour le détail. Résumé :

![Architecture cible](../diagrams/architecture-cible.png)

| Zone | VLAN | Réseau | Passerelle | Hôtes documentés |
|---|---|---|---|---|
| WAN | – | 192.168.100.0/24 | 192.168.100.2 | pfSense : 192.168.100.14 (DHCP) |
| LAN | 10 | 10.10.10.0/24 | 10.10.10.1 | poste d'administration 10.10.10.100, poste de test 10.10.10.101 |
| SERVEURS | 20 | 10.10.20.0/24 | 10.10.20.1 | `srv-syslog` 10.10.20.5 |
| DMZ | 30 | 10.10.30.0/24 | 10.10.30.1 | `srv-web` 10.10.30.6 |

**Fonctionnement [RÉEL]** :

1. Un seul lien **trunk 802.1Q** relie `vtnet1` de pfSense à Gi0/0 de SW1. pfSense route et filtre entre les VLAN.
2. Le filtrage stateful (pfSense) applique une politique par zone. Le refus est la règle par défaut.
3. Suricata inspecte le trafic **déjà autorisé** sur trois interfaces (WAN, DMZ, LAN).
4. pfSense envoie journaux pare-feu et alertes vers `srv-syslog`, situé dans la zone SERVEURS.

**Choix d'architecture argumentés dans le rapport d'origine** :

- *Segmentation en zones plutôt que réseau plat renforcé* : règles différenciées par zone, réduction du domaine de propagation, isolement de la DMZ.
- *Suricata plutôt que Snort* : multi-thread natif et journalisation EVE JSON. Le rapport d'origine cite aussi des débits (≈ 90 Mbps pour Snort, ≈ 140 Mbps pour Suricata) : **aucun protocole ni mesure correspondants ne figurent dans les preuves fournies** ; ces chiffres ne sont donc pas repris ici.
- *IDS sur le LAN, blocage sur WAN et DMZ* : limiter le risque de blocage intempestif du trafic métier interne.
- *Solution entièrement libre* : pfSense CE, Suricata, règles ET Open.

## 4. Technologies, outils et versions

| Catégorie | Élément | Version / valeur | Statut |
|---|---|---|---|
| Pare-feu | pfSense CE | **2.8.1** (schéma de config XML 22.9) | [RÉEL] |
| IDS/IPS | Suricata (paquet pfSense) | **7.0.2** (`suricata-7.0.2_1`) | [RÉEL] |
| Règles | Emerging Threats Open | mise à jour du 2026-09-06 03:43 UTC (MD5 `c54d129abe82cb1b14376f4a8cb9617d`) | [RÉEL] |
| Système de la VM pfSense | FreeBSD (base de pfSense), ZFS, virtio | – | [RÉEL] (noyau/version FreeBSD non capturés) |
| Matériel de la VM | 2 vCPU (QEMU Virtual CPU 2.4.0), 4032 MiB RAM, 16 Go de disque, 2 NIC `vtnet` | – | [RÉEL] |
| Switch | SW1, VLAN 10/20/30, trunk 802.1Q | modèle et version | [À CONFIRMER] |
| Serveur web | Ubuntu + nginx | nginx **1.18.0** | [RÉEL] (version d'Ubuntu : [À CONFIRMER]) |
| Serveur Syslog | Linux (`srv-syslog`) | distribution, démon | [À CONFIRMER] |
| Attaquant simulé | Kali Linux, Nmap, Hydra | Nmap **7.99**, Hydra **v9.6** | [RÉEL] |
| Plateforme de virtualisation | Adresses MAC `50:00:00:xx` et style de topologie compatibles EVE-NG | – | [À CONFIRMER] |

## 5. Prérequis matériels et logiciels

**Matériels (valeurs de la maquette) [RÉEL]** : VM pfSense de 2 vCPU, 4 Go de RAM et 16 Go de disque ; deux interfaces réseau virtio ; ressources suffisantes pour les VM `srv-web`, `srv-syslog`, le poste de test Kali, un poste d'administration et le switch.

**Logiciels [RÉEL]** : image d'installation pfSense CE 2.8.1 (Netgate) ; paquet `pfSense-pkg-suricata` (installé depuis le gestionnaire de paquets de pfSense) ; nginx sur `srv-web` ; un démon syslog sur `srv-syslog` ; Nmap et Hydra sur le poste de test.

**Réseau** : un accès Internet côté WAN (installation du paquet Suricata et téléchargement des règles) ; un switch capable de VLAN et de trunk 802.1Q.

**Compétences** : VLAN, routage inter-VLAN, filtrage stateful et NAT, lecture de journaux, notions d'IDS/IPS.

Liste complète, y compris comptes et droits : [`guide-deploiement.md`](guide-deploiement.md#0-prérequis).

## 6. Étapes de conception et de mise en œuvre

Chronologie **reconstituée à partir des horodatages des preuves** (UTC). Les dates précises de certaines étapes ne sont pas visibles ; elles sont signalées.

| Date (UTC) | Étape | Preuve |
|---|---|---|
| 2026-09-04 21:44 | Téléchargement de pfSense CE 2.8.1 | `screenshots/00-…` |
| 2026-09-05 15:26 et 17:22 | Schémas de l'architecture existante puis cible | `diagrams/architecture-existante.png`, `architecture-cible.png` |
| 2026-09-05 (jusqu'à 17:11) | Installation initiale de pfSense (LAN 192.168.1.1/24) | `config/pfsense-baseline-avant-segmentation-assainie.xml` |
| 2026-09-05 16:16 – 17:07 | **Mesures de référence** sur le réseau à plat : Nmap, Hydra, ping, charge CPU | tests A1 à A6 |
| 2026-09-05 17:24 | Création des VLAN 10/20/30 et du trunk sur SW1 | `screenshots/20-…` |
| 2026-09-05 18:21 – 18:36 | Affectation des interfaces et des VLAN sur pfSense ; adressage ; alias | `screenshots/21-…`, `22-…`, `23-…` |
| 2026-09-05 18:46 – 19:30 | Création des règles LAN, DMZ, SERVEURS (horodatage des règles) | `config/regles-pare-feu.md` |
| 2026-09-05 19:49 | Redirections de ports 80 et 443 vers `srv-web` | `screenshots/27-…`, `65-…` |
| 2026-09-06 02:24 – 03:00 | Mesures après segmentation, **avant Suricata** (CPU, temps HTTP) | tests B2 à B5 |
| 2026-09-06 02:54 | Ajout de la règle « LAN vers DNS pfSense » | `config/regles-pare-feu.md` |
| 2026-09-06 03:04 – 03:08 | Installation du paquet Suricata | `screenshots/40-…` à `42-…` |
| 2026-09-06 03:43 | Téléchargement des règles ET Open | `screenshots/43-…` |
| 2026-09-06 04:11 | Instances Suricata en mode **Inline IPS** (WAN, DMZ) | `screenshots/44-…` |
| 2026-09-06 04:21 | Ajout de la règle « SERVEURS vers DNS pfSense » | `config/regles-pare-feu.md` |
| 2026-09-06 05:17 | Journalisation distante vers `10.10.20.5:514` | `screenshots/50-…` |
| 2026-09-06 05:34 | Premier test de flux interdit LAN → DMZ | `screenshots/60-…` |
| 2026-09-07 00:30 – 00:57 | Scan Nmap complet ; instances passées en **Legacy Mode** (00:34) ; alertes reçues sur `srv-syslog` (00:42) | `screenshots/45-…`, `61-…` |
| 2026-09-07 01:08 | Export de la configuration finale | `config/pfsense-config-assainie.xml` |
| 2026-09-07 02:13 – 02:37 | Scan `-sV`, alertes dans l'interface, journal du blocage LAN → DMZ | `screenshots/62-…`, `63-…`, `64-…` |

**Méthode de pilotage** : cinq phases pondérées (cadrage 10 %, conception 25 %, réalisation 35 %, validation 20 %, bilan 10 %) sur un calendrier de huit semaines défini par le dossier de projets (schéma [`diagrams/phases-projet.png`](../diagrams/phases-projet.png)). Les preuves techniques du dépôt couvrent la période du 4 au 7 septembre 2026.

Procédure de reproduction pas à pas : [`guide-deploiement.md`](guide-deploiement.md).

## 7. Configuration détaillée

| Sujet | Contenu | Fichier |
|---|---|---|
| Système pfSense | Nom d'hôte `pfSense`, domaine `home.arpa`, fuseau `Etc/UTC`, interface en français, NTP `2.pfsense.pool.ntp.org`, interface web en **HTTP**, **SSH activé**, un seul compte local (`admin`, groupe `admins`) | `config/pfsense-config-assainie.xml` |
| Interfaces | WAN `vtnet0` DHCP, blocage des bogons ; LAN `vtnet1.10` 10.10.10.1/24 ; DMZ `vtnet1.30` 10.10.30.1/24 ; SERVEURS `vtnet1.20` 10.10.20.1/24 | README, `screenshots/21-…`, `22-…` |
| DHCP | Uniquement sur le LAN : plage 10.10.10.100 – 10.10.10.200, DNS diffusés 8.8.8.8 et 1.1.1.1 | export XML |
| DNS | Résolveur Unbound activé, sans restriction d'interface | export XML |
| Alias, règles, NAT | 4 alias, 20 règles, 2 redirections | [`config/regles-pare-feu.md`](../config/regles-pare-feu.md) |
| Suricata | 3 instances, ET Open, 26 fichiers de règles, mise à jour hebdomadaire | [`config/suricata.md`](../config/suricata.md) |
| Switch | VLAN 10/20/30, trunk Gi0/0 | [`config/sw1-switch.md`](../config/sw1-switch.md) |
| Journalisation | Système + pare-feu vers `10.10.20.5:514`, source interface SERVEURS | [`config/syslog-serveur.md`](../config/syslog-serveur.md) |

**Paramètres à adapter** pour un autre environnement : adresse et passerelle WAN (ici obtenues en DHCP), plan d'adressage 10.10.x.0/24, alias (adresses des postes d'administration, du serveur web, du serveur Syslog), nom des interfaces virtuelles si la plateforme diffère (`vtnet0`/`vtnet1`), planification des mises à jour de règles.

## 8. Tests réalisés et résultats

Le détail (commandes, résultats bruts, preuves) est dans [`tests/plan-de-tests.md`](../tests/plan-de-tests.md). Résultats principaux **[RÉEL]** :

| Domaine | Résultat |
|---|---|
| Référence sans segmentation | Scan abouti (22, 80 ouverts) ; mot de passe SSH retrouvé en 3 s ; ping moyen 2,214 ms ; CPU 3 % (repos), 9 % (test) |
| Segmentation | LAN → DMZ : HTTP sans réponse (133 305 ms) et ICMP bloqué et journalisé ; DMZ → LAN : bloqué et journalisé ; DMZ → DNS externe : bloqué par la règle finale |
| Surface exposée sur l'adresse WAN | Sur 65 535 ports, 65 533 filtrés ; 53/tcp (Unbound) et 80/tcp (nginx 1.18.0) répondent ; 443/tcp fermé |
| Détection | Alerte `ET SCAN Possible Nmap User-Agent Observed` (SID 2024364, priorité 1) visible dans Suricata (instance DMZ) et reçue sur `srv-syslog` |
| Journalisation | Blocages `filterlog` et alertes Suricata reçus sur `srv-syslog` |
| Temps HTTP après segmentation (sans Suricata) | ≈ 13 ms vers le web DMZ via le WAN (12,3 à 17,2 ms) ; 159 à 239 ms vers Internet (+ une valeur à 1,845 s) |

**Non démontré par les preuves fournies** : blocage effectif d'une source par Suricata ; attaque par force brute après déploiement ; latence et CPU avec Suricata actif ; nombre de règles chargées ; taux de détection et de faux positifs (tests D1 à D7).

## 9. Problèmes rencontrés et solutions

| # | Problème | Constat [RÉEL] | Solution / état |
|---|---|---|---|
| P1 | **Mode Inline IPS abandonné** | Le mode « Inline IPS » (WAN, DMZ) est visible le 6 septembre à 04:11 ; le 7 septembre à 00:34 et dans l'export, le mode est **Legacy** | Passage en Legacy Mode (blocage des hôtes fautifs par table du pare-feu). **Cause exacte : [À RENSEIGNER]** |
| P2 | **DNS bloqué par la politique** | Les journaux montrent des requêtes DNS vers 8.8.8.8 et 1.1.1.1 bloquées (poste LAN, `srv-web`) ; les règles « vers DNS pfSense » du LAN et de SERVEURS ont été ajoutées le 6 septembre, après les règles initiales | Résolution via pfSense (Unbound) autorisée pour LAN et SERVEURS. **Reste** : le DHCP du LAN diffuse toujours 8.8.8.8 / 1.1.1.1 ; la DMZ n'a aucune règle DNS |
| P3 | **Alertes Suricata absentes des journaux centralisés pour WAN et DMZ** | L'export montre alertes vers syslog et EVE activés sur l'instance LAN seulement | Non corrigé dans la configuration finale **[RECOMMANDATION]** : activer l'envoi sur WAN et DMZ |
| P4 | **Scan complet très long** | Le scan `-p1-65535 --script vuln` dure 702,68 s car presque tous les ports sont filtrés | Constat utile pour planifier les tests : limiter les ports ou augmenter le rythme pour la reproduction |

Les causes de P1 et les corrections de P3 sont à compléter par l'auteur : ne pas les affirmer sans preuve.

## 10. Mesures de sécurité mises en place

### 10.1 En place **[RÉEL]**

| Domaine | Mesure |
|---|---|
| Segmentation | 3 zones, un seul trunk ; routage inter-VLAN uniquement par pfSense |
| Filtrage | Refus par défaut ; ouvertures explicites par zone ; blocages inter-zones **journalisés** (LAN→DMZ, DMZ→LAN, DMZ→SERVEURS, DMZ→tout, SERVEURS→LAN, SERVEURS→DMZ) |
| Isolement DMZ | Aucun flux vers LAN ou SERVEURS, sauf `srv-web` → syslog:514 |
| Administration | Accès aux serveurs (445, 3389) réservé à l'alias `Postes_Admin` ; un seul compte local |
| Exposition | Seuls 80 et 443 sont redirigés vers la DMZ ; blocage des bogons sur le WAN ; 65 533 ports filtrés sur l'adresse WAN |
| Détection | Suricata sur WAN, DMZ, LAN ; règles ET Open ; mises à jour tous les 7 jours à 03:00 |
| Réaction | Blocage des sources fautives **configuré** (`blockoffenders`) sur WAN et DMZ, mode Legacy (effet non démontré, voir § 11) |
| Traçabilité | Journaux pare-feu et système déportés vers `srv-syslog` ; journalisation des changements de configuration |
| Éthique des tests | Tests d'attaque limités à la maquette, environnement maîtrisé |

### 10.2 Faiblesses connues (à corriger avant toute réutilisation)

Constats **[RÉEL]**, avec correction proposée **[RECOMMANDATION]** :

| # | Constat | Risque | Correction proposée **[RECOMMANDATION]** |
|---|---|---|---|
| S1 | Interface web pfSense en **HTTP** (port 80) | Identifiants en clair sur le réseau | Passer en HTTPS |
| S2 | **SSH activé** | Surface d'administration supplémentaire | Désactiver ou restreindre à `Postes_Admin`, authentification par clé |
| S3 | **Règle anti-blocage** : tout le LAN atteint pfSense sur 80 et 22 | L'alias `Postes_Admin` ne protège pas l'administration de pfSense | Désactiver l'anti-blocage, règle dédiée à `Postes_Admin` |
| S4 | Communauté SNMP `public` présente dans la config | Fuite d'informations si le service est activé (activation non prouvée) **[À CONFIRMER]** | Supprimer ou renommer, ne pas activer sans nécessité |
| S5 | Unbound écoute sans restriction d'interface et 53/tcp répond sur l'adresse WAN lors des scans | Résolveur potentiellement joignable depuis le WAN (à vérifier depuis un vrai côté WAN) | Limiter Unbound aux interfaces LAN et SERVEURS |
| S6 | Règles « LAN vers Internet Web » et « SERVEURS vers Internet MAJ » avec destination `any` | Ouverture 80/443 vers les autres réseaux internes non bloqués explicitement | Alias « tout sauf RFC1918 » |
| S7 | DHCP diffusant 8.8.8.8 / 1.1.1.1 | Incohérence avec la politique DNS ; contournement du résolveur | DNS du DHCP = 10.10.10.1 |
| S8 | Serveur web sans HTTPS (443 fermé) | Trafic web en clair | Certificat et écoute 443 sur `srv-web` |
| S9 | Pas d'authentification renforcée ni de sauvegarde automatisée documentées | Perte ou compromission du compte unique | 2FA / compte nominatif, sauvegarde chiffrée planifiée |
| S10 | VLAN native du trunk = VLAN 1, ports inutilisés non désactivés sur SW1 | Durcissement du switch incomplet | VLAN native dédiée, `shutdown` des ports inutilisés |

## 11. Limites actuelles

**[RÉEL]**

- **Blocage IPS non démontré** : les scans C6 et C7 ont abouti ; l'action visible dans l'interface est « alerte ». La liste de passage `default` peut exempter les réseaux locaux du blocage **[À CONFIRMER]**.
- **Origine des scans** : la source est 10.10.10.101 (VLAN 10). Aucun test depuis une machine réellement côté WAN n'est documenté.
- **Journalisation incomplète des alertes** (P3) et format texte plutôt que JSON.
- **Pas de test de force brute après déploiement** ; pas de mesure de charge avec Suricata ; pas de test de non-régression fonctionnelle documenté au-delà des flux testés.
- **Nœud unique** : pas de haute disponibilité ; pas de supervision continue ni de sauvegarde automatique.
- **Maquette** : trafic réduit, aucun débit de production ; résultats non extrapolables à un environnement réel.
- Faiblesses S1 à S10 ci-dessus.

## 12. Améliorations et évolutions possibles

**[AMÉLIORATION]** (aucune n'est réalisée) :

| Priorité | Amélioration |
|---|---|
| Haute | Corriger S1 à S7 ; activer l'envoi des alertes WAN/DMZ vers syslog |
| Haute | Démontrer le blocage : source hors liste de passage, capture de l'onglet *Blocks* ; documenter la cause du retour du mode Inline vers Legacy et tester à nouveau le mode Inline |
| Moyenne | Campagne complète après Suricata : force brute (Hydra), scan lent, mesures de latence, de débit et de CPU comparables à la référence |
| Moyenne | Export EVE JSON vers un SIEM (Wazuh, ELK), corrélation, tableaux de bord et alertes |
| Moyenne | Haute disponibilité CARP, VLAN de management, sauvegardes chiffrées automatisées |
| Basse | Intégration de listes de réputation (Feodo, ABUSE.ch) ; réglage fin des règles et suppression des faux positifs |
| Basse | Automatisation du déploiement (scripts, Ansible, sauvegarde de configuration versionnée) |

## 13. Conclusion

**[RÉEL]** La maquette est passée d'un réseau à plat, où un scan aboutit et où un mot de passe SSH est retrouvé en quelques secondes, à une architecture segmentée en trois zones, avec un service unique publié en DMZ et une politique de filtrage dont les blocages inter-zones sont journalisés. L'adresse WAN n'expose que deux ports sur 65 535 lors des scans réalisés (lancés depuis le VLAN 10, voir § 11). Suricata détecte un scan Nmap (SID 2024364) et les événements sont centralisés sur un serveur dédié.

**Ce que le projet n'a pas encore prouvé** : le blocage effectif par Suricata, le comportement face à une attaque par force brute après déploiement et l'impact mesuré sur les performances. Ces points sont inscrits comme travaux restants, avec les preuves à produire (partie D du plan de tests).

**Retour d'expérience [RÉEL]** : la politique de moindre privilège impose de traiter explicitement les dépendances (ici le DNS) ; le refus implicite se lit dans les journaux et fait apparaître les oublis ; un mode de blocage doit être validé par un test, pas seulement par sa configuration.

## 14. Annexes

### Annexe A : correspondance affirmations ↔ preuves

| Affirmation | Preuve |
|---|---|
| pfSense CE 2.8.1 | `screenshots/00-…` |
| 2 vCPU, 4 Go, 16 Go ZFS | `screenshots/28-…` |
| VLAN 10/20/30 sur `vtnet1` | `screenshots/21-…`, `config/pfsense-config-assainie.xml` |
| Adresses des interfaces | `screenshots/22-…` |
| Trunk SW1 | `screenshots/20-…` |
| Règles et NAT | `screenshots/24-…` à `27-…`, `config/regles-pare-feu.md` |
| Suricata 7.0.2, ET Open | `screenshots/40-…` à `43-…` |
| Modes de blocage | `screenshots/44-…`, `45-…` |
| Journalisation distante | `screenshots/50-…` |
| Blocages et alertes | `screenshots/60-…` à `64-…`, `tests/logs/extraits-journaux.md` |


### Annexe B : analyse de risques du rapport d'origine (cotation qualitative de l'auteur)

Échelle probabilité × impact de 1 (faible) à 3 (élevé). Ces cotations sont **des estimations**, pas des mesures.

| Risque | Prob. | Impact | Cotation | Mesure de réduction |
|---|---|---|---|---|
| Intrusion externe via un flux non filtré | 2 | 3 | 6 | Politique de filtrage par zone, moindre privilège |
| Exfiltration de données depuis la DMZ | 2 | 3 | 6 | Isolement de la DMZ, règles de sortie restrictives |
| Déni de service / saturation du pare-feu | 1 | 2 | 2 | Dimensionnement, règles anti-flood, supervision de la charge |
| Scan ou force brute non détecté | 3 | 2 | 6 | IDS/IPS, alertes centralisées |
