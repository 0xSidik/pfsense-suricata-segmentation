#!/usr/bin/env python3
"""
Assainit un export de configuration pfSense (config.xml) avant publication.

Remplace par la valeur REDACTED :
  - <bcrypt-hash>, <password>, <md5-hash>, <sha512-hash>   (mots de passe / hash)
  - <crt>, <prv>                                            (certificat et clé privée)
  - <xmldata> dans <sshdata>                                (clés d'hôte SSH)
  - <authorizedkeys>, <ipsecpsk>, <pre-shared-key>, <key>   (clés, PSK)

Usage :
    python3 sanitize-pfsense-config.py config.xml config/pfsense-config-assainie.xml

Le fichier produit est destiné à la DOCUMENTATION : il n'est plus importable
tel quel dans pfSense (certificat et clés supprimés).

IMPORTANT : relire le résultat (grep -n -i -E "REDACTED|BEGIN|password|key") avant
tout `git add`. Ne jamais publier l'export brut.
"""
import re
import sys

TAGS = [
    "bcrypt-hash", "password", "md5-hash", "sha512-hash",
    "crt", "prv", "xmldata",
    "authorizedkeys", "ipsecpsk", "pre-shared-key",
]


def sanitize(text: str) -> str:
    for tag in TAGS:
        pattern = re.compile(
            r"(<%s>)(.*?)(</%s>)" % (re.escape(tag), re.escape(tag)), re.DOTALL
        )
        text = pattern.sub(r"\1REDACTED\3", text)
    return text


def main() -> None:
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    with open(sys.argv[1], encoding="utf-8") as f:
        original = f.read()
    cleaned = sanitize(original)
    with open(sys.argv[2], "w", encoding="utf-8") as f:
        f.write(cleaned)
    print("OK -> %s (%d octets -> %d octets)" % (sys.argv[2], len(original), len(cleaned)))


if __name__ == "__main__":
    main()
