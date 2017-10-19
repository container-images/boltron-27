#! /bin/sh -e


for i in $@; do
    if [ "x$i" = "all" ]; then
        continue
    fi

    mkdir /LOCAL/$i
    cd /LOCAL/$i

    /mbs-cli dlmod $i

    createrepo .
    mv *.modmd modules.yaml
    modifyrepo modules.yaml repodata
done

cd /LOCAL
/m2c.py merge all $@
createrepo all
mv all/modmd all/modules.yaml
modifyrepo all/modules.yaml all/repodata
rm -rf /var/cache/dnf/local*
/list-modules-py3.py
dnf -y module install $@
