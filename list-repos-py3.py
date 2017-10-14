#! /usr/bin/python3

import dnf

from dnf.i18n import _, ucd
from dnf.pycomp import long


import operator

import time

base = dnf.Base()
base.read_all_repos()
base.fill_sack()

repos = list(base.repos.iter_enabled())
repos.sort(key=operator.attrgetter('id'))

def _num2ui_num(num):
    return ucd(dnf.pycomp.format("%d", num, True))

def format_number(number, SI=0, space=' '):
    """Return a human-readable metric-like string representation
    of a number.

    :param number: the number to be converted to a human-readable form
    :param SI: If is 0, this function will use the convention
       that 1 kilobyte = 1024 bytes, otherwise, the convention
       that 1 kilobyte = 1000 bytes will be used
    :param space: string that will be placed between the number
       and the SI prefix
    :return: a human-readable metric-like string representation of
       *number*
    """

    # copied from from urlgrabber.progress
    symbols = [ ' ', # (none)
                'k', # kilo
                'M', # mega
                'G', # giga
                'T', # tera
                'P', # peta
                'E', # exa
                'Z', # zetta
                'Y'] # yotta

    if SI: step = 1000.0
    else: step = 1024.0

    thresh = 999
    depth = 0
    max_depth = len(symbols) - 1

    if number is None:
        number = 0.0

    # we want numbers between 0 and thresh, but don't exceed the length
    # of our list.  In that event, the formatting will be screwed up,
    # but it'll still show the right number.
    while number > thresh and depth < max_depth:
        depth  = depth + 1
        number = number / step

    if isinstance(number, int) or isinstance(number, long):
        format = '%i%s%s'
    elif number < 9.95:
        # must use 9.95 for proper sizing.  For example, 9.99 will be
        # rounded to 10.0 with the .1f format string (which is too long)
        format = '%.1f%s%s'
    else:
        format = '%.0f%s%s'

    return(format % (float(number or 0), space, symbols[depth]))

def ui_time(tm):
    return time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(tm))


def _repo_size(sack, repo):
    ret = 0
    for pkg in sack.query().filter(reponame__eq=repo.id):
        ret += pkg._size
    return format_number(ret)

for repo in repos:
    num = len(base.sack.query().filter(reponame__eq=repo.id))
    ui_num = _num2ui_num(num)
    ui_size = _repo_size(base.sack, repo)
    rev = ''
    tm = ''
    md = repo.metadata
    if md and md._revision is not None:
        rev = md._revision
        tm = ui_time(md._md_timestamp)
    print(repo.id, ui_num, ui_size, rev, tm)

