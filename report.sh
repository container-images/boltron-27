#! /bin/sh -e


toaddr="dev.null@example.com"
fromaddr="Auto CI <bot@example.com>"

if [ -f .email.conf ]; then
. ./.email.conf
fi

image="jamesantill/boltron-27"
dock="sudo docker"
dockimage="$dock images $image"
dockrun="sudo docker run --rm -it $image"

tests="test-$(cat latest-Fedora-Modular-27.COMPOSE_ID)"
otests="test-$(cat prev-Fedora-Modular-27.COMPOSE_ID)"
if [ ! -d $tests ]; then
    exit 1
fi

rm -f /tmp/out.$$
echo " Auto CI for image $image:" > /tmp/out.$$
$dockimage:latest --format='ID: {{.ID}}' --no-trunc >> /tmp/out.$$
echo -n '    ' >> /tmp/out.$$
$dockimage:latest --format='Size   : {{.Size}}' >> /tmp/out.$$
echo -n '    ' >> /tmp/out.$$
$dockimage:latest --format='Created: {{.CreatedAt}}' >> /tmp/out.$$
echo "    Base   : $(cat latest-Fedora-Modular-27.COMPOSE_ID)" >> /tmp/out.$$
if [ -f prev-Fedora-Modular-27.COMPOSE_ID ]; then
echo "    Prev   : $(cat prev-Fedora-Modular-27.COMPOSE_ID)" >> /tmp/out.$$
fi
if false; then
echo "    Bike   : $($dockrun cat latest-Fedora-Modular-Bikeshed.COMPOSE_ID)" >> /tmp/out.$$
echo "    Prev   : $($dockrun:$(cat prev-Fedora-Modular-27.COMPOSE_ID) cat latest-Fedora-Modular-Bikeshed.COMPOSE_ID)" >> /tmp/out.$$
fi

echo "" >> /tmp/out.$$

echo "==================================================" >> /tmp/out.$$
printf "%30s\n" "Summary" >> /tmp/out.$$
echo "--------------------------------------------------" >> /tmp/out.$$
tm=$(perl -MFile::stat -le '$num = stat($ARGV[0] . ".STATUS")->mtime - stat($ARGV[0] . ".COMPOSE_ID")->mtime; $h = int($num / 60); if ($h >= 60) { printf "%2d:%02d:%02d", int($h / 60), $h % 60, $num % 60 } else { printf "   %d:%02d", $h, $num % 60 }' latest-Fedora-Modular-27)
echo " Compose taken: $tm" >> /tmp/out.$$
tm=$(perl -MFile::stat -le '$num = stat($ARGV[0] . "/end")->mtime - stat($ARGV[0] . "/beg")->mtime; $h = int($num / 60); if ($h >= 60) { printf "%2d:%02d:%02d", int($h / 60), $h % 60, $num % 60 } else { printf "   %d:%02d", $h, $num % 60 }' $tests)
echo " Tests taken  : $tm" >> /tmp/out.$$
echo " Modules      : $(wc -l < $tests/mods)" >> /tmp/out.$$
echo " Tests        : $(wc -l < $tests/out)" >> /tmp/out.$$
echo "    PASS: $(fgrep pass $tests/out | wc -l)" >> /tmp/out.$$
echo "    FAIL: $(fgrep FAIL $tests/out | wc -l)" >> /tmp/out.$$
echo "        FAIL dnf err : $(fgrep 'FAIL: DNF' $tests/out | wc -l)" >> /tmp/out.$$
echo "        FAIL dnf skip: $(fgrep 'FAIL: Did' $tests/out | wc -l)" >> /tmp/out.$$
echo "" >> /tmp/out.$$

if [ -f prev-Fedora-Modular-27.COMPOSE_ID ]; then
if ! diff -u $otests/mods $tests/mods > /dev/null; then
echo "==================================================" >> /tmp/out.$$
printf "%30s\n" "Modules diff" >> /tmp/out.$$
echo "--------------------------------------------------" >> /tmp/out.$$
diff -u $otests/mods $tests/mods >> /tmp/out.$$ || true
fi

if ! diff -u $otests/repos $tests/repos > /dev/null; then
echo "==================================================" >> /tmp/out.$$
printf "%30s\n" "Repos change diff" >> /tmp/out.$$
echo "--------------------------------------------------" >> /tmp/out.$$
diff -u $otests/repos $tests/repos >> /tmp/out.$$ || true
else
echo "==================================================" >> /tmp/out.$$
printf "%30s\n" "Repos" >> /tmp/out.$$
echo "--------------------------------------------------" >> /tmp/out.$$
cat $tests/repos >> /tmp/out.$$
fi

if ! diff -u $otests/rpm $tests/rpm > /dev/null; then
echo "==================================================" >> /tmp/out.$$
printf "%30s\n" "RPM change diff" >> /tmp/out.$$
echo "--------------------------------------------------" >> /tmp/out.$$
diff -u $otests/rpm $tests/rpm >> /tmp/out.$$ || true
else
echo "==================================================" >> /tmp/out.$$
printf "%30s\n" "RPM" >> /tmp/out.$$
echo "--------------------------------------------------" >> /tmp/out.$$
cat $tests/rpm >> /tmp/out.$$
fi

else
# No previous image ...
echo "==================================================" >> /tmp/out.$$
printf "%30s\n" "Modules" >> /tmp/out.$$
echo "--------------------------------------------------" >> /tmp/out.$$
cat $tests/mods >> /tmp/out.$$ || true
echo "==================================================" >> /tmp/out.$$
printf "%30s\n" "Repos" >> /tmp/out.$$
echo "--------------------------------------------------" >> /tmp/out.$$
cat $tests/repos >> /tmp/out.$$
echo "==================================================" >> /tmp/out.$$
printf "%30s\n" "RPM" >> /tmp/out.$$
echo "--------------------------------------------------" >> /tmp/out.$$
cat $tests/rpm >> /tmp/out.$$
fi
echo "" >> /tmp/out.$$

echo "" >> /tmp/out.$$
echo " Full output:" >> /tmp/out.$$
cat $tests/out >> /tmp/out.$$
echo "" >> /tmp/out.$$
echo "" >> /tmp/out.$$
echo " Full image used data:" >> /tmp/out.$$
cat $tests/hdr >> /tmp/out.$$

perl -i -pe 's/\r//g' /tmp/out.$$

if [ "x$1" = "xemail" ]; then
if [ "x$(fgrep pass $tests/out | wc -l)" != "x$(wc -l < $tests/out)" ]; then
mail -n -r "$fromaddr" -s "Modularity Image $(sudo docker images jamesantill/boltron-27:latest --format='ID: {{.ID}}') FAIL: $(fgrep FAIL $tests/out | wc -l)/$(wc -l < $tests/out)" "$toaddr" < /tmp/out.$$
fi
rm -f /tmp/out.$$
exit 0
fi

for i in $(fgrep 'FAIL: DNF' $tests/out | awk '{ print $1 }'); do
    j="$(echo $i | tr '/' '-')"
echo "==================================================" >> /tmp/out.$$
printf "%30s\n" "Test output: $i" >> /tmp/out.$$
echo "--------------------------------------------------" >> /tmp/out.$$
if [ -s $tests/out-$j-1 ]; then
echo "--------------------------------------------------" >> /tmp/out.$$
printf "%30s\n" "stdout" >> /tmp/out.$$
echo "--------------------------------------------------" >> /tmp/out.$$
cat $tests/out-$j-1  >> /tmp/out.$$
fi
if [ -s $tests/out-$j-2 ]; then
echo "--------------------------------------------------" >> /tmp/out.$$
printf "%30s\n" "STDERR" >> /tmp/out.$$
echo "--------------------------------------------------" >> /tmp/out.$$
cat $tests/out-$j-2  >> /tmp/out.$$
fi
done

if [ "x$1" = "xemail-force" ]; then
mail -n -r "$fromaddr" -s "Modularity Image $(sudo docker images jamesantill/boltron-27:latest --format='ID: {{.ID}}') FAIL: $(fgrep FAIL $tests/out | wc -l)/$(wc -l < $tests/out)" "$toaddr" < /tmp/out.$$
rm -f /tmp/out.$$
exit 0
fi

echo "Subject: Modularity Image $(sudo docker images jamesantill/boltron-27:latest --format='ID: {{.ID}}') FAIL: $(fgrep FAIL $tests/out | wc -l)/$(wc -l < $tests/out)"

cat /tmp/out.$$

rm -f /tmp/out.$$
