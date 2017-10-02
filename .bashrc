# .bashrc

# User specific aliases and functions

# Source global definitions
if [ -f /etc/bashrc ]; then
	. /etc/bashrc
fi

 PS1='Boltron-27-\h-$?# '
 alias ls="/bin/ls --block-size=\'1 --color=auto --sort=version --time-style=long-iso -F -T 0"
 alias l='ls -ABFbs'
 alias ll='l -BFabls'
 alias lsz='l --sort=size -r'
 alias llsz='ll --sort=size -r'

if [ -f /image-data ]; then
 /image-data
fi
