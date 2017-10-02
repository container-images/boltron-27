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
 echo "DNF: https://copr.fedorainfracloud.org/coprs/mhatina/DNF-Modules/"
 dnf --disablerepo=\* list installed dnf libdnf
 rpm -q --qf '%{name} Built on: %{buildtime:date}\n' libdnf
 rpm -q --qf '%{name}    Built on: %{buildtime:date}\n' dnf
 echo "----------------------------------------------------------------------"

 echo "Image built with (KOJI composes):"
 echo -e "\t\tGIT:      \thttps://github.com/container-images/boltron-27"
 echo -e "\t\tBase:     \t$(cat latest-Fedora-Modular-27.COMPOSE_ID)"
 echo -e "\t\tBikeshed: \t$(cat latest-Fedora-Modular-Bikeshed.COMPOSE_ID)"
 echo "Image running aginst (KOJI Composes):"
 echo -e "\t\tBase:     \t$(curl -s https://kojipkgs.fedoraproject.org/compose/latest-Fedora-Modular-27/COMPOSE_ID)"
 echo -e "\t\tBikeshed: \t$(curl -s https://kojipkgs.fedoraproject.org/compose/latest-Fedora-Modular-Bikeshed/COMPOSE_ID)"
 echo "Image running aginst (Modularity server):"
 echo -e "  http://modularity.fedorainfracloud.org/modularity/hack-fedora-f27-mods/..."
 echo -e "\t\tMaven:    \tmaven-@master-20170923133034"
 echo -e "\t\tMySQL:    \tmysql-@master-20170904221942"
 echo -e "\t\tninja:    \tninja-@master-20170904182925"
 echo -e "\t\tnodejs:   \tnodejs-@6-20170925160215"
 echo -e "\t\tnodejs:   \tnodejs-@master-20170925073359"
