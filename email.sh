#! /bin/sh -e

if [ ! -f tests-out ]; then
    exit 1
fi

toaddr="dev.null@example.com"
fromaddr="Auto CI <bot@example.com>"

if [ -f .email.conf ]; then
. ./.email.conf
fi

rm -f /tmp/out.$$
echo " Auto CI for image jamesantill/boltron-27:" > /tmp/out.$$
sudo docker images jamesantill/boltron-27 --format='ID: {{.ID}}' --no-trunc >> /tmp/out.$$
echo -n '    ' >> /tmp/out.$$
sudo docker images jamesantill/boltron-27 --format='Size   : {{.Size}}' >> /tmp/out.$$
echo -n '    ' >> /tmp/out.$$
sudo docker images jamesantill/boltron-27 --format='Created: {{.CreatedAt}}' >> /tmp/out.$$
echo "    Base   : $(cat latest-Fedora-Modular-27.COMPOSE_ID)" >> /tmp/out.$$
if [ -f prev-Fedora-Modular-27.COMPOSE_ID ]; then
echo "    Prev   : $(cat prev-Fedora-Modular-27.COMPOSE_ID)" >> /tmp/out.$$
fi

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
echo "" >> /tmp/out.$$
echo " Full output:" >> /tmp/out.$$
cat tests-out >> /tmp/out.$$
echo "" >> /tmp/out.$$
echo "" >> /tmp/out.$$
echo " Full image used data:" >> /tmp/out.$$
cat tests-hdr >> /tmp/out.$$

if [ "x$(fgrep pass tests-out | wc -l)" != "x$(wc -l < tests-out)" ]; then
perl -i -pe 's/\r//g' /tmp/out.$$
mail -n -r "$fromaddr" -s "Modularity Image $(sudo docker images jamesantill/boltron-27 --format='ID: {{.ID}}') FAIL: $(fgrep FAIL tests-out | wc -l)/$(wc -l < tests-out)" "$toaddr" < /tmp/out.$$
fi

rm -f /tmp/out.$$
