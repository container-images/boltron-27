#! /bin/sh -e

# Download the latest composed image, import it into docker
# Eg.
# https://kojipkgs.fedoraproject.org/compose/latest-Fedora-Modular-27/compose/Server/x86_64/images/Fedora-Modular-Docker-Base-27_Modular-20170927.n.0.x86_64.tar.xz

curl="curl --progress-bar --fail --compressed --remote-time --location -O"
modtype="27"
modurl="https://kojipkgs.fedoraproject.org/compose/latest-Fedora-Modular-$modtype"
dualimages=true

rm -f COMPOSE_ID
$curl $modurl/COMPOSE_ID
ID="$(cat COMPOSE_ID)"
OID=""

if [ -f latest-Fedora-Modular-27.COMPOSE_ID ]; then
OID="$(cat latest-Fedora-Modular-27.COMPOSE_ID)"
    if [ "x$OID" != "x$ID" ]; then
        exit 0
    fi
rm -f COMPOSE_ID
        exit 1
fi
        exit 0
