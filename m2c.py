#! /usr/bin/python

import os
import sys
import shutil
import fnmatch

import gzip

import yaml

# import yum
import rpm
import stat
# import rpmUtils
# check if rpm has the new weakdeps tags
_rpm_has_new_weakdeps = hasattr(rpm, 'RPMTAG_ENHANCENAME')

modmd_only = False
build_rpm = True

if len(sys.argv) < 2:
    _usage()

maincmd = sys.argv[1]
nsubcmds = len(sys.argv) - 2

def _usage(code=1):
    print >>sys.stderr, """\
 Args: <cmd> ...
    convert       <outdir> <Combined modmd>
    extract       <outdir> <Combined modmd> <module>...
    list          <Combined modmd>...
    merge         <outdir> <Combined modmd>...
    rename-stream <outdir> <Combined modmd> <newstram> <module>...
    rpms          <Combined modmd>...
    help"""
    sys.exit(code)

if False: pass
elif maincmd == 'list':
    if nsubcmds < 1:
        _usage()

elif maincmd == 'rpms':
    if nsubcmds < 1:
        _usage()

elif maincmd == 'extract':
    if nsubcmds < 3:
        _usage()

    outdir = sys.argv[2]

    if not os.path.exists(outdir):
        os.makedirs(outdir)

elif maincmd == 'rename-stream':
    if nsubcmds < 4:
        _usage()

    outdir = sys.argv[2]

    if not os.path.exists(outdir):
        os.makedirs(outdir)

elif maincmd == 'merge':
    if nsubcmds < 2:
        _usage()

    outdir = sys.argv[2]

    if not os.path.exists(outdir):
        os.makedirs(outdir)

elif maincmd == 'convert':
    if nsubcmds < 2:
        _usage()
    outdir = sys.argv[2]

    if outdir[0] != '/':
        outdir = os.getcwd() + '/' + outdir

    if not os.path.exists(outdir):
        os.makedirs(outdir)

elif maincmd == 'help':
    _usage(0)
else:
    _usage()

# Everyone needs a modmd...
def _get_modmd(arg):
    modmd  = arg

    if os.path.isdir(modmd) and os.path.isdir(modmd + "/repodata"):
        import glob
        modmds = glob.glob(modmd + "/repodata/*modules.yaml*")
        if modmds:
            modmd = modmds[0]

    if modmd.endswith(".gz"):
        modmd = gzip.open(modmd)
    else:
        modmd = open(modmd)
    return modmd

# Blacklist config. files ... So we can not convert some mods/rpms.
blacklist = {'rpms' : {}, 'mods' : {}}
def _read_blacklist(fname):
    if not os.path.exists(fname):
        return None
    ret = []
    for line in open(fname):
        line = line.strip()
        if line and line[0] == '#':
            continue
        ret.append(line)
    return ret
def _read_blacklists(dname, ext):
    ret = _read_blacklist("%s/blacklist-n-%s.conf" % (dname, ext))
    if ret is None:
        ret = _read_blacklist("%s/../blacklist-n-%s.conf" % (dname, ext))
    return ret or {}
if maincmd == 'convert':
    blacklist['mods'] = _read_blacklists(outdir, "mods")
    blacklist['rpms'] = _read_blacklists(outdir, "rpms")

def version_tuple_to_string(evrTuple):
    """
    Convert a tuple representing a package version to a string.

    @param evrTuple: A 3-tuple of epoch, version, and release.

    Return the string representation of evrTuple.
    """
    (e, v, r) = evrTuple
    s = ""

    if e not in [0, '0', None]:
        s += '%s:' % e
    if v is not None:
        s += '%s' % v
    if r is not None:
        s += '-%s' % r
    return s

def prco_tuple_to_string(prcoTuple):
    """returns a text string of the prco from the tuple format"""

    (name, flag, evr) = prcoTuple
    flags = {'GT':'>', 'GE':'>=', 'EQ':'=', 'LT':'<', 'LE':'<='}
    if flag is None:
        return name

    return '%s %s %s' % (name, flags[flag], version_tuple_to_string(evr))

def nevra_split(nevra):
    """Take a full nevra string and return a tuple. """
    n, ev, ra = nevra.rsplit('-', 2)
    if ':' in ev:
        e, v = ev.split(':', 1)
    else:
        e, v = '0', ev
    r, a = ra.rsplit('.', 1)
    return n, e, v, r, a

def re_primary_filename(filename):
    """ Tests if a filename string, can be matched against just primary.
        Note that this can produce false negatives (Eg. /b?n/zsh) but not false
        positives (because the former is a perf hit, and the later is a
        failure). Note that this is a superset of re_primary_dirname(). """
    if re_primary_dirname(filename):
        return True
    if filename == '/usr/lib/sendmail':
        return True
    return False

def re_primary_dirname(dirname):
    """ Tests if a dirname string, can be matched against just primary. Note
        that this is a subset of re_primary_filename(). """
    if 'bin/' in dirname:
        return True
    if dirname.startswith('/etc/'):
        return True
    return False

def initReadOnlyTransaction(root='/'):
    read_ts = rpm.TransactionSet(root)
    read_ts.setVSFlags((rpm._RPMVSF_NOSIGNATURES|rpm._RPMVSF_NODIGESTS))
    return read_ts

def hdrFromPackage(ts, package):
    """hand back the rpm header or raise an Error if the pkg is fubar"""
    try:
        fdno = os.open(package, os.O_RDONLY)
    except OSError, e:
        raise

    try:
        hdr = ts.hdrFromFdno(fdno)
    except rpm.error, e:
        os.close(fdno)
        raise ValueError, "RPM Error opening Package"
    if type(hdr) != rpm.hdr:
        os.close(fdno)
        raise ValueError, "RPM Error opening Package (type)"

    os.close(fdno)
    return hdr

def flagToString(flags):
    flags = flags & 0xf

    if flags == 0: return None
    elif flags == 2: return 'LT'
    elif flags == 4: return 'GT'
    elif flags == 8: return 'EQ'
    elif flags == 10: return 'LE'
    elif flags == 12: return 'GE'

    return flags

def stringToVersion(verstring):
    if verstring in [None, '']:
        return (None, None, None)
    i = verstring.find(':')
    if i != -1:
        try:
            epoch = str(long(verstring[:i]))
        except ValueError:
            # look, garbage in the epoch field, how fun, kill it
            epoch = '0' # this is our fallback, deal
    else:
        epoch = '0'
    j = verstring.find('-')
    if j != -1:
        if verstring[i + 1:j] == '':
            version = None
        else:
            version = verstring[i + 1:j]
        release = verstring[j + 1:]
    else:
        if verstring[i + 1:] == '':
            version = None
        else:
            version = verstring[i + 1:]
        release = None
    return (epoch, version, release)

def comparePoEVR(po1, po2):
    """
    Compare two Package or PackageEVR objects.
    """
    (e1, v1, r1) = (po1.epoch, po1.version, po1.release)
    (e2, v2, r2) = (po2.epoch, po2.version, po2.release)
    return rpm.labelCompare((e1, v1, r1), (e2, v2, r2))

# HACK: This is completely retarded. Don't blame me, someone just fix
#       rpm-python already. This is almost certainly not all of the problems,
#       but w/e.
def _rpm_long_size_hack(hdr, size):
    """ Rpm returns None, for certain sizes. And has a "longsize" for the real
        values. """
    return hdr[size] or hdr['long' + size]

class cpkg(object):
    def __init__(self, filename):
        ts = initReadOnlyTransaction()
        hdr = hdrFromPackage(ts, filename)
        self.hdr = hdr
        self.epoch = self.doepoch()
        self.ver = self.version
        self.rel = self.release
        self.pkgtup = (self.name, self.arch, self.epoch, self.ver, self.rel)

        self.pkgid = self.hdr[rpm.RPMTAG_SHA1HEADER]
        if not self.pkgid:
            self.pkgid = "%s.%s" %(self.hdr['name'], self.hdr['buildtime'])
        self.packagesize = _rpm_long_size_hack(self.hdr, 'archivesize')
        self.installedsize = _rpm_long_size_hack(self.hdr, 'size')

        self.__mode_cache = {}
        self.__prcoPopulated = False
        self._loadedfiles = False
        self.prco = {}
        self.prco['obsoletes'] = [] # (name, flag, (e,v,r))
        self.prco['conflicts'] = [] # (name, flag, (e,v,r))
        self.prco['requires'] = [] # (name, flag, (e,v,r))
        self.prco['provides'] = [] # (name, flag, (e,v,r))
        self.prco['suggests'] = [] # (name, flag, (e,v,r))
        self.prco['enhances'] = [] # (name, flag, (e,v,r))
        self.prco['recommends'] = [] # (name, flag, (e,v,r))
        self.prco['supplements'] = [] # (name, flag, (e,v,r))
        self.files = {}
        self.files['file'] = []
        self.files['dir'] = []
        self.files['ghost'] = []


    def __getattr__(self, thing):
        # API - if an error - return AttributeError, not KeyError
        if thing.startswith('__') and thing.endswith('__'):
            # If these existed, then we wouldn't get here ...
            # So these are missing.
            raise AttributeError, "%s has no attribute %s" % (self, thing)
        try:
            return self.hdr[thing]
        except KeyError:
            #  Note above, API break to fix this ... this at least is a nicer
            # msg. so we know what we accessed that is bad.
            raise KeyError, "%s has no attribute %s" % (self, thing)
        except ValueError:
            #  Note above, API break to fix this ... this at least is a nicer
            # msg. so we know what we accessed that is bad.
            raise ValueError, "%s has no attribute %s" % (self, thing)

    def __str__(self):
        if self.epoch == '0':
            val = '%s-%s-%s.%s' % (self.name, self.version, self.release,
                                   self.arch)
        else:
            val = '%s-%s:%s-%s.%s' % (self.name, self.epoch, self.version,
                                      self.release, self.arch)
        return val

    def verCMP(self, other):
        """ Compare package to another one, only rpm-version ordering. """
        if not other:
            return 1
        ret = cmp(self.name, other.name)
        if ret == 0:
            ret = comparePoEVR(self, other)
        return ret

    def __cmp__(self, other):
        """ Compare packages, this is just for UI/consistency. """
        ret = self.verCMP(other)
        if ret == 0:
            ret = cmp(self.arch, other.arch)
        return ret

    def _size(self):
        return _rpm_long_size_hack(self.hdr, 'size')

    size     = property(fget=lambda x: x._size)

    def doepoch(self):
        tmpepoch = self.hdr['epoch']
        if tmpepoch is None:
            epoch = '0'
        else:
            epoch = str(tmpepoch)

        return epoch

    def _returnPrco(self, prcotype, printable=False):
        """return list of provides, requires, conflicts or obsoletes"""

        prcotype = {"weak_requires" : "recommends",
                    "info_requires" : "suggests",
                    "weak_reverse_requires" : "supplements",
                    "info_reverse_requires" : "enhances"}.get(prcotype, prcotype)
        prcos = self.prco.get(prcotype, [])

        if printable:
            results = []
            for prco in prcos:
                if not prco[0]: # empty or none or whatever, doesn't matter
                    continue
                results.append(prco_tuple_to_string(prco))
            return results

        return prcos

    def returnPrco(self, prcotype, printable=False):
        if not self.__prcoPopulated:
            self._populatePrco()
            self.__prcoPopulated = True
        return self._returnPrco(prcotype, printable)

    def _populatePrco(self):
        "Populate the package object with the needed PRCO interface."

        tag2prco = { "OBSOLETE": "obsoletes",
                     "CONFLICT": "conflicts",
                     "REQUIRE":  "requires",
                     "PROVIDE":  "provides" }

        def _end_nfv(name, flag, vers):
            flag = map(flagToString, flag)

            vers = map(stringToVersion, vers)
            vers = map(lambda x: (x[0], x[1], x[2]), vers)

            return zip(name,flag,vers)

        hdr = self.hdr
        for tag in tag2prco:
            name = hdr[getattr(rpm, 'RPMTAG_%sNAME' % tag)]
            if not name: # empty or none or whatever, doesn't matter
                continue

            lst = hdr[getattr(rpm, 'RPMTAG_%sFLAGS' % tag)]
            if tag == 'REQUIRE':
                #  Rpm is a bit magic here, and if pkgA requires(pre/post): foo
                # it will then let you remove foo _after_ pkgA has been
                # installed. So we need to mark those deps. as "weak".
                #  This is not the same as recommends/weak_requires.
                bits = rpm.RPMSENSE_SCRIPT_PRE | rpm.RPMSENSE_SCRIPT_POST
                weakreqs = [bool(flag & bits) for flag in lst]

            vers = hdr[getattr(rpm, 'RPMTAG_%sVERSION' % tag)]
            prcotype = tag2prco[tag]
            self.prco[prcotype] = _end_nfv(name, lst, vers)
            if tag == 'REQUIRE':
                weakreqs = zip(weakreqs, self.prco[prcotype])
                strongreqs = [wreq[1] for wreq in weakreqs if not wreq[0]]
                self.prco['strong_requires'] = strongreqs

        # This looks horrific as we are supporting both the old and new formats:
        tag2prco = { "SUGGEST":    ( "suggests",
                                     1156, 1157, 1158, 1 << 27, 0),
                     "ENHANCE":    ( "enhances",
                                     1159, 1160, 1161, 1 << 27, 0),
                     "RECOMMEND":  ( "recommends",
                                     1156, 1157, 1158, 1 << 27, 1 << 27),
                     "SUPPLEMENT": ( "supplements",
                                     1159, 1160, 1161, 1 << 27, 1 << 27) }
        for tag in tag2prco:
            (prcotype, oldtagn, oldtagv, oldtagf, andmask, resmask) = tag2prco[tag]
            name = None
            if _rpm_has_new_weakdeps:
                name = hdr[getattr(rpm, 'RPMTAG_%sNAME' % tag)]
            if not name:
                name = hdr[oldtagn]
                if not name:
                    continue
                (name, flag, vers) = self._filter_deps(name, hdr[oldtagf], hdr[oldtagv], andmask, resmask)
            else:
                flag = hdr[getattr(rpm, 'RPMTAG_%sFLAGS' % tag)]
                vers = hdr[getattr(rpm, 'RPMTAG_%sVERSION' % tag)]
            if not name: # empty or none or whatever, doesn't matter
                continue
            self.prco[prcotype] = _end_nfv(name, flag, vers)

    def _loadFiles(self):
        files = self.hdr['filenames']
        fileflags = self.hdr['fileflags']
        filemodes = self.hdr['filemodes']
        filetuple = zip(files, filemodes, fileflags)
        if not self._loadedfiles:
            for (fn, mode, flag) in filetuple:
                #garbage checks
                if mode is None or mode == '':
                    if 'file' not in self.files:
                        self.files['file'] = []
                    self.files['file'].append(fn)
                    continue
                if mode not in self.__mode_cache:
                    self.__mode_cache[mode] = stat.S_ISDIR(mode)

                fkey = 'file'
                if self.__mode_cache[mode]:
                    fkey = 'dir'
                elif flag is not None and (flag & 64):
                    fkey = 'ghost'
                self.files.setdefault(fkey, []).append(fn)

            self._loadedfiles = True

    def _returnFileEntries(self, ftype='file', primary_only=False):
        """return list of files based on type, you can pass primary_only=True
           to limit to those files in the primary repodata"""
        if self.files:
            if ftype in self.files:
                if primary_only:
                    if ftype == 'dir':
                        match = re_primary_dirname
                    else:
                        match = re_primary_filename
                    return [fn for fn in self.files[ftype] if match(fn)]
                return self.files[ftype]
        return []

    def returnFileEntries(self, ftype='file', primary_only=False):
        """return list of files based on type"""
        self._loadFiles()
        return self._returnFileEntries(ftype,primary_only)


def iter_mods(modmd):
    return sorted(modmd, key=lambda x: (x['data']['name'],
                                        x['data']['stream'],
                                        x['data'].get('version', '')))

def write_modmd(fname, modmd):
    fo = open(fname + ".tmp", 'w')
    print >>fo, yaml.dump_all(modmd, explicit_start=True)
    os.rename(fname + '.tmp', fname)

def read_modmd(fo):
    return list(yaml.load_all(fo))

def iter_nevras(nevras):
    for nevra in sorted(nevras):
        n,e,v,r,a = nevra_split(nevra)
        if a == 'src': continue
        rpm_fname = "%s-%s-%s.%s.rpm" % (n, v, r, a)
        yield n,e,v,r,a

def mod_fname2rpmdir(mod_fname):
    rpmdir = mod_fname
    if not os.path.isdir(rpmdir):
        rpmdir = os.path.dirname(mod_fname)
    if os.path.basename(rpmdir) == 'repodata':
        rpmdir = os.path.dirname(rpmdir)
    if os.path.exists(rpmdir + '/Packages'):
        rpmdir += '/Packages'
    return rpmdir

def iter_rpms(mod, mod_fname):
    artifacts = mod['data']['artifacts']
    for n,e,v,r,a in iter_nevras(artifacts['rpms']):
        rpm_fname = "%s-%s-%s.%s.rpm" % (n, v, r, a)

        rpmdir = mod_fname2rpmdir(mod_fname)

        filename = rpmdir + '/' + rpm_fname
        if not os.path.exists(filename):
            filename = rpmdir + '/' + n[0].lower() + '/' + rpm_fname
        if not os.path.exists(filename):
            filename = None
        yield (n,e,v,r,a), (rpm_fname, filename)

def copy_rpms(outdir, mod, mod_fname):
    for (n,e,v,r,a), (rpm_fname, filename) in iter_rpms(mod, mod_fname):
        if filename is None:
            print >>sys.stderr, " Warning: RPM NOT FOUND:", rpm_fname
            continue
        print "Copying RPM:", rpm_fname
        shutil.copy2(filename, outdir)

def _mn(mod):
    return mod['data']['name']
def _mns(mod):
    return mod['data']['name'] + '-' + mod['data']['stream']
def _mnsv(mod):
    ver = str(mod['data']['version'])
    mnv = mod['data']['name'] + '-' + mod['data']['stream'] + '-' + ver
    return mnv
def _mnsv_ui(mod, expand=0):
    ver = str(mod['data']['version'])
    mnv = mod['data']['name'] + '-' + mod['data']['stream']
    if expand > len(mnv):
        mnv += ' ' * (expand - len(mnv))
    mnv += ' ' + ver
    return mnv

def matched_iter_mods(modmd, ids):
    for mod in iter_mods(modmd):
        for uid in ids:
            if fnmatch.fnmatch(_mn(mod), uid):
                break
            if fnmatch.fnmatch(_mns(mod), uid):
                break
            if fnmatch.fnmatch(_mnsv(mod), uid):
                break
        else:
            continue
        yield mod

def _max_ns(mods):
    return max((len(_mns(mod)) for mod in iter_mods(modmd)))

if False: pass

elif maincmd == 'list':
    for arg in sys.argv[2:]:
        modmd =  _get_modmd(arg)
        modmd = read_modmd(modmd)
        expand = _max_ns(modmd)
        num = 0
        for mod in iter_mods(modmd):
            num += 1
            prog = "(%*d/%d)" % (len(str(len(modmd))), num, len(modmd))
            mn = _mnsv_ui(mod, expand)
            print mn, prog
    sys.exit(0)

elif maincmd == 'rpms':
    for arg in sys.argv[2:]:
        modmd =  _get_modmd(arg)
        modmd = read_modmd(modmd)
        expand = _max_ns(modmd)
        num = 0
        for mod in iter_mods(modmd):
            num += 1
            prog = "(%*d/%d)" % (len(str(len(modmd))), num, len(modmd))
            mn = _mnsv_ui(mod, expand)
            print '=' * 79
            print ' ' * 10, mn, prog
            print '-' * 79
            for (n,e,v,r,a), (rpm_fname, filename) in iter_rpms(mod, arg):
                if filename is None:
                    print '  **', rpm_fname
                else:
                    print '    ', rpm_fname
    sys.exit(0)

elif maincmd == 'merge':
    allmodmd = {}
    mod_fnames = {}
    for arg in sys.argv[3:]:
        modmd =  _get_modmd(arg)
        modmd = read_modmd(modmd)
        for mod in iter_mods(modmd):
            allmodmd[_mnsv(mod)] = mod
            mod_fnames[_mnsv(mod)] = arg

    mmods = list(iter_mods(allmodmd.values()))
    
    num = 0
    for mod in mmods:
        num += 1
        prog = "(%*d/%d)" % (len(str(len(modmd))), num, len(modmd))
        mn = _mnsv_ui(mod)
        print '=' * 79
        print ' ' * 30, mn, prog
        print '-' * 79

        copy_rpms(outdir, mod, mod_fnames[_mnsv(mod)])

    write_modmd(outdir + '/' + 'modmd', mmods)
    sys.exit(0)

elif maincmd == 'extract':
    mod_fname = sys.argv[3]
    modmd =  _get_modmd(mod_fname)
    modmd = read_modmd(modmd)
    ids = set(sys.argv[4:])
    mmods = list(matched_iter_mods(modmd, ids))
        
    num = 0
    for mod in mmods:
        num += 1
        prog = "(%*d/%d)" % (len(str(len(mmods))), num, len(mmods))
        mn = _mnsv_ui(mod)
        print '=' * 79
        print ' ' * 30, mn, prog
        print '-' * 79

        copy_rpms(outdir, mod, mod_fname)

    write_modmd(outdir + '/' + 'modmd', mmods)
    sys.exit(0)

elif maincmd == 'rename-stream':
    mod_fname = sys.argv[3]
    modmd =  _get_modmd(mod_fname)
    modmd = read_modmd(modmd)
    nstream = sys.argv[4]
    ids = set(sys.argv[5:])
    mmods = list(matched_iter_mods(modmd, ids))
    expand = _max_ns(modmd)

    num = 0
    for mod in mmods:
        num += 1
        prog = "(%*d/%d)" % (len(str(len(mmods))), num, len(mmods))
        mn = _mnsv_ui(mod, expand)
        mod['data']['stream'] = nstream
        nmn = _mnsv_ui(mod)
        print '=' * 79
        print mn, prog
        print '  ', '=>', nmn
        print '-' * 79

    write_modmd(outdir + '/' + 'modmd', mmods)
    sys.exit(0)

elif maincmd == 'convert':
    pass # Below...

modmd = sys.argv[3]
rpmdir = mod_fname2rpmdir(modmd)
modmd = _get_modmd(modmd)
modmd = list(yaml.load_all(modmd))
num = 0
for mod in iter_mods(modmd):
    num += 1
    prog = "(%*d/%d)" % (len(str(len(modmd))), num, len(modmd))
    if mod['data']['name'] in blacklist['mods']:
        print '=' * 79
        print ' ' * 15, "Blacklisted module:", mod['data']['name'], prog
        print '-' * 79
        continue

    mn = _mns(mod)
    print '=' * 79
    print ' ' * 30, mn, prog
    print '-' * 79
    if 'api' in mod['data']:
        api = mod['data']['api']

        # Change non-blocklisted names in api/rpms
        nrpms = []
        for n in api['rpms']:
            if n not in blacklist['rpms']:
                n = mn + '-' + n
        nrpms.append(n)
        api['rpms'] = nrpms

    artifacts = mod['data']['artifacts']
    nevras = artifacts['rpms'] # Need old ones for below...

    # Change non-blocklisted nevras in artifacts/rpms
    nnevras = []
    for nevra in nevras:
        n,e,v,r,a = nevra_split(nevra)
        if n not in blacklist['rpms']:
            nevra = mn + '-' + nevra
        nnevras.append(nevra)
    artifacts['rpms'] = nnevras

    if 'profiles' in mod['data']:
        for profile in mod['data']['profiles']:
            profile = mod['data']['profiles'][profile]
            # Change non-blocklisted names in profile/rpms
            nrpms = []
            for n in profile['rpms']:
                if n not in blacklist['rpms']:
                    n = mn + '-' + n
            nrpms.append(n)
            profile['rpms'] = nrpms

    if modmd_only:
        nevras = []

    pkgs = []
    for nevra in sorted(nevras):
        n,e,v,r,a = nevra_split(nevra)
        if a == 'src': continue
        rpm_fname = "%s-%s-%s.%s.rpm" % (n, v, r, a)
        filename = rpmdir + '/' + rpm_fname
        if not os.path.exists(filename):
            filename = rpmdir + '/' + n[0].lower() + '/' + rpm_fname
        if not os.path.exists(filename):
            print >>sys.stderr, " Warning: RPM NOT FOUND:", rpm_fname
            continue
        if n in blacklist['rpms']:
            if not build_rpm:
                print "Blacklisted RPM:", nevra
            else:
                print "Copying RPM:", nevra
                odir = "%s/%s" % (outdir, a)
                shutil.copy2(filename, odir)
            continue
        print "Loading:", nevra
        pkg = cpkg(filename=filename)
        pkgs.append(pkg)

    # Allowed prco data has to be within module:
    modprovs = set()
    for pkg in pkgs:
        for (n, f, (e, v, r)) in pkg.returnPrco('provides'):
            modprovs.add(n)

    for pkg in sorted(pkgs):
        n, a, e, v, r = pkg.pkgtup
        rpm_fname = "%s-%s-%s.%s.rpm" % (n, v, r, a)
        filename = rpmdir + '/' + rpm_fname
        if not os.path.exists(filename):
            filename = rpmdir + '/' + n[0].lower() + '/' + rpm_fname

        nn = mn + '-' + pkg.name
        if build_rpm:
            if os.path.exists("%s/%s/%s-%s" % (outdir, a, mn, rpm_fname)):
                print "Cached:", pkg
                continue
        print "Rebuilding:", pkg

        os.system("rpm2cpio " + filename + " > " + nn + "-built.cpio")
        os.system("tar -cf " + nn + ".tar " + nn + "-built.cpio")
        os.remove(nn + "-built.cpio")
        os.system("gzip -f -9 " + nn + ".tar")

        spec = open(nn + ".spec", "w")
        noarch = ''
        if a == 'noarch':
            noarch = "BuildArch: noarch"

        provides, requires, conflicts, obsoletes = '', '', '', ''
        # FIXME: weak-requires/info-requires dito enhances BS.
        for data in pkg.returnPrco('provides'):
            if data[0] not in modprovs:
                continue
            data = prco_tuple_to_string(data)
            provides += 'Provides: %s-%s\n' % (mn, data)

        for data in pkg.returnPrco('requires'):
            if data[0] not in modprovs:
                continue
            data = prco_tuple_to_string(data)
            requires += 'Requires: %s-%s\n' % (mn, data)

        for data in pkg.returnPrco('conflicts'):
            if data[0] not in modprovs:
                continue
            data = prco_tuple_to_string(data)
            conflicts += 'Conflicts: %s-%s\n' % (mn, data)
        # FIXME: obs. wtf

        scriptlet = {}

        for sname, tname in (("pre", "prein"), ("preun", None),
                             ("post", "postin"), ("postun", None),
                             ("pretrans", None), ("posttrans", None)):
            if tname is None:
                tname = sname
            scriptlet[sname] = ''
            prog = getattr(pkg, tname + "prog")
            if not prog:
                continue
            assert len(prog) == 1
            prog = prog[0]
            scriptlet[sname] = """\
%%%s -p %s
%s
""" % (sname, prog, getattr(pkg, tname) or '')
        # FIXME: preinflags

        filelist = \
        "\n".join(pkg.returnFileEntries('file')).replace(" ", "?") + "\n"
        # FIXME: other files, and file attributes
        # "\n".join(pkg.files['ghost']) +
        # "\n".join(pkg.files['dir']) +

        print >>spec, """\

%%define _sourcedir %s
%%define _srcrpmdir %s
%%define _rpmdir %s

%%define __os_install_post :
%%define __spec_install_post :

%%global __requires_exclude_from ^.*$
%%global __provides_exclude_from ^.*$
%%global __requires_exclude ^.*$
%%global __provides_exclude ^.*$

Name:       %s
Epoch:      %s
Version:    %s
Release:    %s
Summary:    %s

License:    %s
URL:        %s

# Provides/Requires/Conflicts/Obsoletes ... Namespaced:
%s
%s
%s
%s

BuildRequires: cpio
%s

Source0: %%{name}.tar.gz

%%description
%s

# Scriptlets...
%s
%s
%s
%s
%s
%s

%%prep
%%setup -c -q

%%install
mkdir -p $RPM_BUILD_ROOT
cp -a %%{name}-built.cpio $RPM_BUILD_ROOT
cd $RPM_BUILD_ROOT
cpio -dium < %%{name}-built.cpio
rm %%{name}-built.cpio

%%files
%s

""" % (os.getcwd(), outdir, outdir, nn, 
       pkg.epoch, pkg.version, pkg.release,
       pkg.summary, pkg.license, pkg.url,
       provides, requires, conflicts, obsoletes,
       noarch, pkg.description,
       scriptlet['pre'], scriptlet['preun'],
       scriptlet['post'], scriptlet['postun'],
       scriptlet['pretrans'], scriptlet['posttrans'],
       filelist)
        spec.close()

        if build_rpm:
            os.system("rpmbuild -bb " + nn + ".spec --quiet > /dev/null")
        else:
            os.system("rpmbuild -bs " + nn + ".spec --quiet > /dev/null")

        os.remove(nn + ".spec")
        os.remove(nn + ".tar.gz")

write_modmd(outdir + '/' + 'modmd', modmd)
