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
mv latest-Fedora-Modular-27.COMPOSE_ID prev-Fedora-Modular-27.COMPOSE_ID || \
  true
    fi
else
mv latest-Fedora-Modular-27.COMPOSE_ID prev-Fedora-Modular-27.COMPOSE_ID || \
  true
fi
mv COMPOSE_ID latest-Fedora-Modular-27.COMPOSE_ID

rm -f STATUS
$curl $modurl/STATUS
echo "========================================================================"
echo "Compose ID: $ID"
echo "STATUS: $(cat STATUS)"
echo "------------------------------------------------------------------------"
mv latest-Fedora-Modular-27.STATUS prev-Fedora-Modular-27.STATUS || \
  true
mv STATUS latest-Fedora-Modular-27.STATUS

# Fedora-Modular-Container-Base-27_Modular-20171025.n.3.x86_64.tar.xz 
fname="$(echo $ID | perl -pe 's/^Fedora-Modular-([^-]+)/Fedora-Modular-Container-Base-$1_Modular/')"
cname="$(echo $ID | perl -pe 's/^Fedora-Modular-([^-]+)/Fedora-Modular-Server-$1-x86_64/')"
if [ ! -f ${cname}-CHECKSUM ]; then
     $curl $modurl/compose/Server/x86_64/images/$cname-CHECKSUM
     fgrep $fname $cname-CHECKSUM > $cname-CHECKSUM-$fname
fi
if [ ! -f ${fname}.x86_64.tar.xz ]; then
echo $modurl/compose/Server/x86_64/images/${fname}.x86_64.tar.xz
  if $curl $modurl/compose/Server/x86_64/images/${fname}.x86_64.tar.xz && \
     sha256sum -c ${cname}-CHECKSUM-$fname; then
    echo "Got compose Docker image: $ID"
  else
cp -a prev-Fedora-Modular-27.COMPOSE_ID latest-Fedora-Modular-27.COMPOSE_ID || \
  true
cp -a prev-Fedora-Modular-27.STATUS latest-Fedora-Modular-27.STATUS || \
  true
    echo "Failed to get compose Docker image, using old: $OID"
    ID="$OID"
fname="$(echo $ID | perl -pe 's/^Fedora-Modular-([^-]+)/Fedora-Modular-Container-Base-$1/')"
  fi
fi
echo "------------------------------------------------------------------------"

sudo docker load < ${fname}.x86_64.tar.xz

lfname="$(echo $fname | tr '[:upper:]' '[:lower:]')"

perl -i -pe 's/^FROM .*/FROM '"${lfname}.x86_64:latest/" Dockerfile
# sudo make build
