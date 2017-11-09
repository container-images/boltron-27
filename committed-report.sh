#! /bin/sh -e

if [ ! -s COMMITTED ]; then
    echo "No COMMITTED file."
    exit 1
fi

if [ ! -f "$1" ]; then
    echo "No out file."
    exit 1
fi


tr : ' ' <"$1" | tr / ' ' | awk '{ print $1 }' > /tmp/blah.a.$$
tr : ' ' <"$1" | tr / ' ' | fgrep -v pass | awk '{ print $1 }' > /tmp/blah.e.$$

atot=0
etot=0
for i in $(cat COMMITTED); do
    anum="$(egrep "^$i\$" /tmp/blah.a.$$ | wc -l)"
    enum="$(egrep "^$i\$" /tmp/blah.e.$$ | wc -l)"
    atot="$(( $atot + $anum ))"
    etot="$(( $etot + $enum ))"

    if [ "$enum" != "0" ]; then
        echo "Failure for: $i $enum out of $anum"
    fi

done

echo "Totals: $etot failures out of $atot"

rm -f /tmp/blah.?.$$
