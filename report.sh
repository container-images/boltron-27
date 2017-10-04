#! /bin/sh -e

if [ ! -f tests-out ]; then
    exit 1
fi

toaddr="dev.null@example.com"
fromaddr="Auto CI <bot@example.com>"

if [ -f .email.conf ]; then
. ./.email.conf
fi

image="jamesantill/boltron-27"
dock="sudo docker"
dockimage="$dock images $image"
dockrun="sudo docker run --rm -it $image"

rm -f /tmp/out.$$
echo " Auto CI for image jamesantill/boltron-27:" > /tmp/out.$$
$dockimage:latest --format='ID: {{.ID}}' --no-trunc >> /tmp/out.$$
echo -n '    ' >> /tmp/out.$$
$dockimage:latest --format='Size   : {{.Size}}' >> /tmp/out.$$
echo -n '    ' >> /tmp/out.$$
$dockimage:latest --format='Created: {{.CreatedAt}}' >> /tmp/out.$$
echo "    Base   : $(cat latest-Fedora-Modular-27.COMPOSE_ID)" >> /tmp/out.$$
if [ -f prev-Fedora-Modular-27.COMPOSE_ID ]; then
echo "    Prev   : $(cat prev-Fedora-Modular-27.COMPOSE_ID)" >> /tmp/out.$$
fi
echo "    Bike   : $($dockrun cat latest-Fedora-Modular-Bikeshed.COMPOSE_ID)" >> /tmp/out.$$
echo "    Prev   : $($dockrun:$(cat prev-Fedora-Modular-27.COMPOSE_ID) cat latest-Fedora-Modular-Bikeshed.COMPOSE_ID)" >> /tmp/out.$$

echo "" >> /tmp/out.$$

echo "==================================================" >> /tmp/out.$$
printf "%30s\n" "Summary" >> /tmp/out.$$
echo "--------------------------------------------------" >> /tmp/out.$$
tm=$(perl -MFile::stat -le '$num = stat("tests-end")->mtime - stat("tests-beg")->mtime; print int($num / 60), ":", $num % 60')
echo " Time taken: $tm" >> /tmp/out.$$
echo " Modules   : $(wc -l < tests-out)" >> /tmp/out.$$
echo "    PASS: $(fgrep pass tests-out | wc -l)" >> /tmp/out.$$
echo "    FAIL: $(fgrep FAIL tests-out | wc -l)" >> /tmp/out.$$
echo "        FAIL dnf err : $(fgrep 'FAIL: DNF' tests-out | wc -l)" >> /tmp/out.$$
echo "        FAIL dnf skip: $(fgrep 'FAIL: Did' tests-out | wc -l)" >> /tmp/out.$$
echo "" >> /tmp/out.$$

if [ -f prev-Fedora-Modular-27.COMPOSE_ID ]; then
diffo="$(cat prev-Fedora-Modular-27.COMPOSE_ID)-list-modules"
diffn="$(cat latest-Fedora-Modular-27.COMPOSE_ID)-list-modules"
sudo docker run --rm -v $(pwd):/mnt  jamesantill/boltron-27:$(cat prev-Fedora-Modular-27.COMPOSE_ID) /mnt/list-modules-py3.py > $diffo
sudo docker run --rm -v $(pwd):/mnt  jamesantill/boltron-27:$(cat latest-Fedora-Modular-27.COMPOSE_ID) /mnt/list-modules-py3.py > $diffn
if ! diff -u $diffo $diffn > /dev/null; then
echo "==================================================" >> /tmp/out.$$
printf "%30s\n" "Modules diff" >> /tmp/out.$$
echo "--------------------------------------------------" >> /tmp/out.$$
diff -u $diffo $diffn >> /tmp/out.$$ || true
fi
rm -f $diffo $diffn

diffo="$(cat prev-Fedora-Modular-27.COMPOSE_ID)-rpm"
diffn="$(cat latest-Fedora-Modular-27.COMPOSE_ID)-rpm"
sudo docker run --rm -v $(pwd):/mnt  jamesantill/boltron-27:$(cat prev-Fedora-Modular-27.COMPOSE_ID) /mnt/list-rpm.sh > $diffo
sudo docker run --rm -v $(pwd):/mnt  jamesantill/boltron-27:$(cat prev-Fedora-Modular-27.COMPOSE_ID) /mnt/list-rpm.sh > $diffn

if ! diff -u $diffo $diffn > /dev/null; then
echo "==================================================" >> /tmp/out.$$
printf "%30s\n" "RPM change diff" >> /tmp/out.$$
echo "--------------------------------------------------" >> /tmp/out.$$
diff -u $diffo $diffn >> /tmp/out.$$ || true
fi
rm -f $diffo $diffn

else
# No previous image ...
echo "==================================================" >> /tmp/out.$$
printf "%30s\n" "Modules" >> /tmp/out.$$
echo "--------------------------------------------------" >> /tmp/out.$$
sudo docker run --rm -v $(pwd):/mnt  jamesantill/boltron-27:$(cat prev-Fedora-Modular-27.COMPOSE_ID) /mnt/list-modules-py3.py >> /tmp/out.$$
fi
echo "" >> /tmp/out.$$

echo "" >> /tmp/out.$$
echo " Full output:" >> /tmp/out.$$
cat tests-out >> /tmp/out.$$
echo "" >> /tmp/out.$$
echo "" >> /tmp/out.$$
echo " Full image used data:" >> /tmp/out.$$
cat tests-hdr >> /tmp/out.$$

perl -i -pe 's/\r//g' /tmp/out.$$

if [ "x$1" = "xemail" ]; then
if [ "x$(fgrep pass tests-out | wc -l)" != "x$(wc -l < tests-out)" ]; then
mail -n -r "$fromaddr" -s "Modularity Image $(sudo docker images jamesantill/boltron-27:latest --format='ID: {{.ID}}') FAIL: $(fgrep FAIL tests-out | wc -l)/$(wc -l < tests-out)" "$toaddr" < /tmp/out.$$
fi
rm -f /tmp/out.$$
exit 0
fi

if [ "x$1" = "xemail-force" ]; then
mail -n -r "$fromaddr" -s "Modularity Image $(sudo docker images jamesantill/boltron-27:latest --format='ID: {{.ID}}') FAIL: $(fgrep FAIL tests-out | wc -l)/$(wc -l < tests-out)" "$toaddr" < /tmp/out.$$
rm -f /tmp/out.$$
exit 0
fi

echo "Subject: Modularity Image $(sudo docker images jamesantill/boltron-27:latest --format='ID: {{.ID}}') FAIL: $(fgrep FAIL tests-out | wc -l)/$(wc -l < tests-out)"

cat /tmp/out.$$

rm -f /tmp/out.$$
