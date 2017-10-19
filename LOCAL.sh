#! /bin/sh -e


for i in $@; do
    if [ "x$i" = "all" ]; then
        continue
    fi

    d="$(echo $i | tr / _)"

    mkdir /LOCAL/MOD-$d
    cd /LOCAL/MOD-$d

    /mbs-cli dlmod $i

    createrepo .
    mv *.modmd modules.yaml
    modifyrepo modules.yaml repodata
done

cd /LOCAL
/m2c.py merge all MOD-*
createrepo all
mv all/modmd all/modules.yaml
modifyrepo all/modules.yaml all/repodata
rm -rf /var/cache/dnf/local*
echo "=================================================="
printf "%30s\n" "Modules"
echo "--------------------------------------------------"
/list-modules-py3.py
echo "--------------------------------------------------"
dnf -y module install $@
