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


# Output by module...
m2rn = {}
for n in rn2m:
    mods = set(map(lambda x: x[0], sorted(rn2m[n])))
    if len(mods) <= 1:
        continue
    # Sort by biggest module intersection first.
    m = (99-len(rn2m[n]), ",".join(mods))
    if m not in m2rn:
        m2rn[m] = set()
    m2rn[m].add(n)
if not m2rn:
    sys.exit(0)
xx = "=" * 20
print(xx, "Modules with duplicate rpms", xx)
for m in sorted(m2rn):
    print("ERROR Duplicate RPMs in modules: ", m[1])
    num = 0
    for n in sorted(m2rn[m]):
        num += 1
        print("%4d" % num, n)

print(xx, "RPMs in multiple modules", xx)
errs = 0
for n in sorted(rn2m):
    mods = set(map(lambda x: x[0], sorted(rn2m[n])))
    if len(mods) <= 1:
        continue
    errs += 1
    print("ERROR (%d) rpm (%s) in %d modules:" % (errs, n, len(rn2m[n])))
    num = 0
    for m in sorted(rn2m[n]):
        num += 1
        print("%4d" % num, "%20s %10s %16s" % m)

