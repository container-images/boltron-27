#! /bin/sh

rpm -q --qf '%{nevra}\n' dnf
# DNF currently has no changelog
# rpm -q --changelog dnf
rpm -q --qf '%{nevra}\n' libdnf
# rpm -q --changelog libdnf
