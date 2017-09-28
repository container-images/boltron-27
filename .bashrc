# .bashrc

# User specific aliases and functions

# Source global definitions
if [ -f /etc/bashrc ]; then
	. /etc/bashrc
fi

if test -x /bin/zsh -a -n "$SSH_TTY"; then
 exec /bin/zsh
fi

 PS1='Boltron-27-\h# '
 alias ls="/bin/ls --block-size=\'1 --color=auto --sort=version --time-style=long-iso -F -T 0"
 alias l='ls -ABFbs'
 alias ll='l -BFabls'
 alias lsz='l --sort=size -r'
 alias llsz='ll --sort=size -r'

 echo "---------------------- This is using a COPR DNF ----------------------"
 echo "DNF:"
 dnf --disablerepo=\* list installed dnf

 echo "Image built with:"
 echo -e "\t\tGIT:      \thttps://github.com/container-images/boltron-27"
 echo -e "\t\tBase:     \t$(cat latest-Fedora-Modular-27.COMPOSE_ID)"
 echo -e "\t\tBikeshed: \t$(cat latest-Fedora-Modular-Bikeshed.COMPOSE_ID)"
 echo "Image running aginst:"
 echo -e "\t\tBase:     \t$(curl -s https://kojipkgs.fedoraproject.org/compose/latest-Fedora-Modular-27/COMPOSE_ID)"
 echo -e "\t\tBikeshed: \t$(curl -s https://kojipkgs.fedoraproject.org/compose/latest-Fedora-Modular-Bikeshed/COMPOSE_ID)"
