#! /usr/bin/python3

import dnf

base = dnf.Base()
base.read_all_repos()
base.fill_sack()

#  This doesn't actually install them, just enables them ... maybe need to
# do a tx or something. Hack it atm.
# base.repo_module_dict.install(['platform:master/buildroot', 'networking-base:master/default', 'hardware-support:master', 'python3:master/default', 'host:master'])


mods = {'platform' :         ('master', 'buildroot'),
        'networking-base' :  ('master', 'default'),
        'hardware-support' : ('master', ''),
        'python3' :          ('master', 'default'),
        'host' :             ('master', ''),
}

for module in base.repo_module_dict.values():
    for stream in module.values():
        for version in stream.values():
            if module.name in mods:
                if mods[module.name][0] != stream.stream: continue

                fo = open("/etc/dnf/modules.d/" + module.name + ".module", "w")
                fo.write('''
[%(name)s]
name = %(name)s
stream = %(stream)s
version = %(version)s
profiles = %(profiles)s
enabled = 1
locked = 0
''' % {'name' : module.name, 'stream' : stream.stream, 'version' : version.version,
    'profiles' : mods[module.name][1]})
                fo.close()
                print("Installing: %20s %10s %16s" % (module.name,stream.stream,version.version))

