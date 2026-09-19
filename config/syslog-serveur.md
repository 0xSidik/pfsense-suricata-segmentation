# Journalisation centralisée (Syslog)

## Côté pfSense [RÉEL]

Chemin : Statut > Journaux système > Paramètres, section « Options de journalisation distante ». Preuve : [`screenshots/50-syslog-distant-configuration.png`](../screenshots/50-syslog-distant-configuration.png) et export XML.

| Paramètre | Valeur |
|---|---|
| Activer la journalisation distante | Oui |
| Adresse source | Interface **SERVEURS** (donc source `10.10.20.1`) |
| Protocole IP | IPv4 |
| Serveur de journalisation distante | `10.10.20.5:514` (aucun 2ᵉ ni 3ᵉ serveur) |
| Contenu | **Événements System** et **Événements du pare-feu** (les autres cases sont décochées) |
| Format | `rfc3164` (BSD) |
| Journaliser les changements de configuration | Activé |
| Rétention locale | 500 entrées, sans compression |
| Descriptions des règles dans les journaux du pare-feu | Activé (`filterdescriptions = 1`) |

Le message affiché par pfSense précise que syslog envoie des datagrammes **UDP** vers le port 514 du serveur, sauf indication contraire.

**Alertes Suricata** : l'instance LAN envoie ses alertes au journal système (facilité `local1`, priorité `notice`), donc vers le serveur distant (voir [`suricata.md`](suricata.md)).

**Flux réseau nécessaire** : pfSense émet depuis 10.10.20.1, dans le même réseau que `srv-syslog` (10.10.20.5). Aucune règle de pare-feu inter-zones n'est requise pour ce sens. Les hôtes du LAN et le serveur web de la DMZ sont autorisés vers `Serveur_Syslog` sur le port 514 (voir [`regles-pare-feu.md`](regles-pare-feu.md)).

## Côté serveur `srv-syslog` (10.10.20.5)

**[RÉEL]** (déduit des captures [`screenshots/61-…`](../screenshots/61-preuves-syslog-blocages-et-alertes.png)) :

- Les événements du pare-feu arrivent dans `/var/log/firewall.log`, les alertes Suricata dans `/var/log/suricata-eve.log`.
- Chaque ligne commence par la date, puis le champ hôte `_gateway`, puis le processus : `filterlog[<pid>]` ou `suricata[<pid>]`.

### Proposition de configuration rsyslog [RECOMMANDATION, non fournie dans les preuves]

À adapter à votre environnement. Elle reproduit la répartition constatée (deux fichiers, séparés par nom de processus).

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
sudo ss -lunp | grep ':514'     # écoute UDP 514
sudo tail -f /var/log/firewall.log
```

**[RECOMMANDATION]** : limiter la source autorisée (10.10.20.1 et les hôtes prévus) au pare-feu local du serveur, mettre en place `logrotate` sur les deux fichiers, synchroniser l'heure (NTP) sur toutes les machines pour corréler les journaux.

## Lire un journal de pare-feu (`filterlog`)

Exemple réel, transcrit de la capture 64 :

```text
Sep  7 02:33:09 _gateway filterlog[23721]: 93,,,1788634015,vtnet1.10,match,block,in,4,0x0,,64,58663,0,DF,1,icmp,84,10.10.10.101,10.10.30.6,request,33151,3264
```

| Champ | Valeur | Sens |
|---|---|---|
| 1ᵉʳ champ | `93` | Numéro de règle (position) |
| 4ᵉ champ | `1788634015` | Identifiant de règle (« tracker ») = « Bloc LAN vers DMZ » |
| 5ᵉ champ | `vtnet1.10` | Interface d'entrée (VLAN 10, LAN) |
| 7ᵉ / 8ᵉ champ | `block` / `in` | Action / sens |
| Après `icmp,84,` | `10.10.10.101,10.10.30.6` | Source, destination |
