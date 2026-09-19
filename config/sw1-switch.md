# Configuration du switch SW1

## Ce qui est prouvé [RÉEL]

Capture : [`screenshots/20-switch-sw1-vlan-et-trunk.png`](../screenshots/20-switch-sw1-vlan-et-trunk.png) (5 septembre 2026, 17:24 UTC).

`show vlan brief` (extrait) :

```text
VLAN Name        Status    Ports
1    default     active    Gi1/0, Gi1/1, Gi1/2, Gi1/3
10   LAN         active    Gi0/1
20   SERVEURS    active    Gi0/2
30   DMZ         active    Gi0/3
```

`show interfaces trunk` :

```text
Port   Mode  Encapsulation  Status    Native vlan
Gi0/0  on    802.1q         trunking  1

Port   Vlans allowed on trunk
Gi0/0  10,20,30

Port   Vlans allowed and active in management domain
Gi0/0  10,20,30

Port   Vlans in spanning tree forwarding state and not pruned
Gi0/0  none
```

Câblage (topologie cible, `diagrams/architecture-cible.png`) :

| Port SW1 | Rôle | Connecté à |
|---|---|---|
| Gi0/0 | Trunk 802.1Q (VLAN 10, 20, 30) | pfSense, interface `e1` / `vtnet1` |
| Gi0/1 | Accès VLAN 10 (LAN) | PC-TEST-LAN |
| Gi0/2 | Accès VLAN 20 (SERVEURS) | SRV-SYSLOG |
| Gi0/3 | Accès VLAN 30 (DMZ) | SRV-WEB-DMZ |

## Commandes reconstituées [RECOMMANDATION : à comparer avec votre `running-config`]

Ces commandes sont **déduites** des sorties `show` ci-dessus. Elles n'ont pas été extraites de l'appareil ; la syntaxe exacte dépend du modèle (sur certains commutateurs, `switchport trunk encapsulation dot1q` est requis avant `switchport mode trunk`).

```text
configure terminal
 vlan 10
  name LAN
 vlan 20
  name SERVEURS
 vlan 30
  name DMZ
 exit
!
interface GigabitEthernet0/0
 description TRUNK-vers-pfSense-vtnet1
 switchport trunk encapsulation dot1q
 switchport mode trunk
 switchport trunk allowed vlan 10,20,30
!
interface GigabitEthernet0/1
 description LAN
 switchport mode access
 switchport access vlan 10
!
interface GigabitEthernet0/2
 description SERVEURS
 switchport mode access
 switchport access vlan 20
!
interface GigabitEthernet0/3
 description DMZ
 switchport mode access
 switchport access vlan 30
end
write memory
```

Vérifications : `show vlan brief`, `show interfaces trunk`, `show interfaces status`.

## Observations

**[RÉEL]**

- La VLAN native du trunk est la VLAN 1 (valeur par défaut). Les ports Gi1/0 à Gi1/3 restent dans la VLAN 1 par défaut.
- La dernière ligne de `show interfaces trunk` indique `none` pour l'état de forwarding Spanning Tree au moment de la capture. Le trafic VLAN est pourtant fonctionnel par la suite (tests du 5 au 7 septembre). Le Spanning Tree n'avait peut-être pas fini de converger à cet instant **[À CONFIRMER]**.

**[RECOMMANDATION]**

- Changer la VLAN native du trunk vers une VLAN inutilisée et arrêter administrativement les ports inutilisés.
- Sauvegarder la configuration du switch dans `config/sw1-running-config.txt` (après retrait des secrets).
