#! /bin/sh -e

if rpm -q createrepo > /dev/null; then
  cre=createrepo
  mod=modifyrepo
else
  if rpm -q createrepo_c > /dev/null; then
    cre=createrepo_c
    mod=modifyrepo_c
  else

    echo "You need to install createrepo or createrepo_c."
    exit 1
  fi
fi

if ! rpm -q python2-rpm > /dev/null; then
  echo "You need to install python2-rpm."
  exit 1
fi

if ! rpm -q PyYAML > /dev/null; then
  echo "You need to install PyYAML."
  exit 1
fi

for i in $@; do
    if [ "x$i" = "all" ]; then
        continue
    fi

    d="$(echo $i | tr / _)"

    mkdir -p /LOCAL/MOD-$d
    cd /LOCAL/MOD-$d

    /mbs-cli dlmod $i

    $cre .
    mv *.modmd modules.yaml
    $mod modules.yaml repodata
done

cd /LOCAL
/m2c.py merge all MOD-*
$cre all
mv all/modmd all/modules.yaml
$mod all/modules.yaml all/repodata
rm -rf /var/cache/dnf/local*
echo "=================================================="
printf "%30s\n" "Modules"
echo "--------------------------------------------------"
/list-modules-py3.py
echo "--------------------------------------------------"
dnf -y module install $@
