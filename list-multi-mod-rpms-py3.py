#! /usr/bin/python3

import dnf

base = dnf.Base()
base.read_all_repos()
base.fill_sack()

mods = []

rn2m = {}

for module in base.repo_module_dict.values():
    for stream in module.values():
        for version in stream.values():
            for nevra in version.nevra():
                n = nevra.rsplit('-', 2)[0]
                d = (module.name, stream.stream, version.version)
                if n not in rn2m:
                    rn2m[n] = []
                rn2m[n].append(d)

errs = 0
for n in sorted(rn2m):
    if len(rn2m[n]) <= 1:
        continue
    errs += 1
    print("ERROR (%d) rpm (%s) in %d modules:" % (errs, n, len(rn2m[n])))
    num = 0
    for m in sorted(rn2m[n]):
        num += 1
        print("%4d" % num, "%20s %10s %16s" % m)

