#! /bin/sh -e

# Download the latest composed image, import it into docker
# Eg.
# https://kojipkgs.fedoraproject.org/compose/latest-Fedora-Modular-27/compose/Server/x86_64/images/Fedora-Modular-Docker-Base-27_Modular-20170927.n.0.x86_64.tar.xz

curl="curl --progress-bar --compressed --remote-time --location -O"
modurl="https://kojipkgs.fedoraproject.org/compose/latest-Fedora-Modular-27"

rm -f COMPOSE_ID
$curl $modurl/COMPOSE_ID
ID="$(cat COMPOSE_ID)"
mv COMPOSE_ID latest-Fedora-Modular-27.COMPOSE_ID

echo "Compose ID: $ID"

fname="$(echo $ID | perl -pe 's/^Fedora-Modular-27/Fedora-Modular-Docker-Base-27_Modular/')"
if [ ! -f ${fname}.x86_64.tar.xz ]; then
  $curl $modurl/compose/Server/x86_64/images/${fname}.x86_64.tar.xz
fi

sudo docker load < ${fname}.x86_64.tar.xz

lfname="$(echo $fname | tr '[:upper:]' '[:lower:]')"

perl -i -pe 's/^FROM .*/FROM '"${lfname}.x86_64:latest/" Dockerfile
# sudo make build
