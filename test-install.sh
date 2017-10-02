#! /bin/sh -e

printf "%24s => " $1
dnf history > /tmp/ohist
if dnf module install -y "$1" 2> /dev/null > /dev/null; then
  dnf history > /tmp/nhist
  if [ "x$(cat /tmp/ohist)" != "x$(cat /tmp/nhist)" ]; then
    echo "   pass"
  else
    echo "** FAIL: Did nothing fast **"
  fi
else
  echo '** FAIL: DNF error **'
fi
