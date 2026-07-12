# ~/.bashrc
# ==============================
# Execução apenas interativa
# ==============================
case $- in
    *i*) ;;
      *) return;;
esac

# ==============================
# Histórico
# ==============================
HISTCONTROL=ignoreboth
HISTSIZE=1000
HISTFILESIZE=2000

shopt -s histappend
shopt -s checkwinsize

# ==============================
# Ambiente
# ==============================
[ -x /usr/bin/lesspipe ] && eval "$(SHELL=/bin/bash lesspipe)"

if [ -z "${debian_chroot:-}" ] && [ -r /etc/debian_chroot ]; then
    debian_chroot=$(< /etc/debian_chroot)
fi

# ==============================
# Prompt (PS1)
# ==============================
case "$TERM" in
    xterm*|rxvt*|*-256color)
	PS1='\[\033[38;5;196m\]╭──(\[\033[38;5;27;1m\]WhoFoss\[\033[38;5;196m\])\[\033[38;5;27m\]-\[\033[38;5;196m\](\[\033[38;5;27m\]$(whoami)\[\033[38;5;196m\])\n\[\033[38;5;196m\]╰─[\[\033[38;5;27m\]\W\[\033[38;5;196m\]]-}\[\033[0m\] '	
        ;;
    *)
        PS1='\[\033[31m\]╭──(\[\033[34;1m\]WhoFoss\[\033[0;31m\])\[\033[34m\]-\[\033[0;31m\](\[\033[34m\]$(whoami)\[\033[0;31m\])\n\[\033[31m\]╰─[\[\033[34m\]\W\[\033[0;31m\]]-}\[\033[0m\] '
        ;;
esac

# ==============================
# Aliases (base)
# ==============================
if [ -x /usr/bin/dircolors ]; then
    eval "$(dircolors -b 2>/dev/null)"
    alias ls='ls --color=auto'
    alias grep='grep --color=auto'
fi

alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'

# ==============================
# Aliases (segurança)
# ==============================
alias rm='rm -i'
alias cp='cp -i'
alias mv='mv -i'

# ==============================
# Aliases (atalhos úteis)
# ==============================
alias df='df -h'
alias du='du -h'
alias h='history'
alias c='clear'
alias e='exit'

# ==============================
# Navegação rápida
# ==============================
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'

############# Função personalizada para cd
cd() {
    if [ "$1" == ".." ]; then
        builtin cd .. && ls
    elif [ -n "$1" ]; then
        builtin cd "$1" && ls
    else
        builtin cd && ls
    fi
}

# ==============================
# Git (atalhos)
# ==============================
alias gita='git add .'
alias gitc='git commit -m'
alias gitp='git push'

# ==============================
# Utilidades extras
# ==============================

# Enviar saída para termbin
alias tb="nc termbin.com 9999 2>/dev/null || echo 'Falha ao conectar com termbin'"

# ==============================
# Funções úteis
# ==============================

extract() {
    if [ -f "$1" ]; then
        case "$1" in
            *.tar.gz) tar xzf "$1" ;;
            *.tar.bz2) tar xjf "$1" ;;
            *.zip) unzip "$1" ;;
            *.rar) unrar x "$1" ;;
            *.7z) 7z x "$1" ;;
            *) echo "Formato não suportado" ;;
        esac
    else
        echo "Arquivo inválido"
    fi
}

genpasswd() {
    local PWDLEN=${1:-32}
    tr -dc A-Za-z0-9_ </dev/urandom | head -c ${PWDLEN}
    echo
}

xtop() {
    local N=${1:-10}
    history | awk '{a[$2]++ } END{for(i in a){print a[i] " " i}}' | sort -rn | head -n $N
}

# ==============================
# Alert
# ==============================
alias alert='notify-send --urgency=low -i "$([ $? = 0 ] && echo terminal || echo error)" "$(history | tail -n1 | sed -e '\''s/^\s*[0-9]\+\s*//;s/[;&|]\s*alert$//'\'')"'

# ==============================
# Arquivos externos
# ==============================
[ -f ~/.bash_aliases ] && . ~/.bash_aliases

if ! shopt -oq posix; then
    [ -f /usr/share/bash-completion/bash_completion ] && . /usr/share/bash-completion/bash_completion
    [ -f /etc/bash_completion ] && . /etc/bash_completion
fi
