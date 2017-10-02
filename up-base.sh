#! /bin/sh -e

# Download the latest composed image, import it into docker
# Eg.
# https://kojipkgs.fedoraproject.org/compose/latest-Fedora-Modular-27/compose/Server/x86_64/images/Fedora-Modular-Docker-Base-27_Modular-20170927.n.0.x86_64.tar.xz

curl="curl --progress-bar --fail --compressed --remote-time --location -O"
modurl="https://kojipkgs.fedoraproject.org/compose/latest-Fedora-Modular-27"

rm -f COMPOSE_ID
$curl $modurl/COMPOSE_ID
ID="$(cat COMPOSE_ID)"
OID=""
mv latest-Fedora-Modular-27.COMPOSE_ID prev-Fedora-Modular-27.COMPOSE_ID || \
  true
mv COMPOSE_ID latest-Fedora-Modular-27.COMPOSE_ID

if [ -f prev-Fedora-Modular-27.COMPOSE_ID ]; then
OID="$(cat prev-Fedora-Modular-27.COMPOSE_ID)"
fi

rm -f STATUS
$curl $modurl/STATUS
echo "========================================================================"
echo "Compose ID: $ID"
echo "STATUS: $(cat STATUS)"
echo "------------------------------------------------------------------------"
mv STATUS latest-Fedora-Modular-27.STATUS

fname="$(echo $ID | perl -pe 's/^Fedora-Modular-27/Fedora-Modular-Docker-Base-27_Modular/')"
if [ ! -f ${fname}.x86_64.tar.xz ]; then
  if $curl $modurl/compose/Server/x86_64/images/${fname}.x86_64.tar.xz; then
    echo "Got compose Docker image: $ID"
  else
    ID="$OID"
    echo "Failed to get compose Docker image, using old: $OID"
fname="$(echo $ID | perl -pe 's/^Fedora-Modular-27/Fedora-Modular-Docker-Base-27_Modular/')"
  fi
fi
echo "------------------------------------------------------------------------"

sudo docker load < ${fname}.x86_64.tar.xz

lfname="$(echo $fname | tr '[:upper:]' '[:lower:]')"

perl -i -pe 's/^FROM .*/FROM '"${lfname}.x86_64:latest/" Dockerfile
# sudo make build
