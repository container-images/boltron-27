#! /bin/sh -e

curl="curl --progress-bar --compressed --remote-time --location -O"
mod="http://modularity.fedorainfracloud.org/modularity/hack-fedora-f27-mods/"

cd /etc/yum.repos.d
$curl $mod/all.repo
cd /etc/dnf/modules.defaults.d
$curl $mod/all.defaults
