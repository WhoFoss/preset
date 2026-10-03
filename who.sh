#!/usr/bin/env bash

#-----------HEADER-------------------------------------------------------------|
# AUTOR             : WhoFoss
# HOMEPAGE          : https://github.com/WhoFoss/preset
# DATA-DE-CRIAÇÃO   : 02/10/2026
# PROGRAMA          : preset.sh
# VERSÃO            : 1.1.0
# PEQUENA-DESCRIÇÃO : Configura o sistema após a instalação: dotfiles, Kitty,
#                     Flatpaks, pacotes APT e AB Download Manager.
# DEPENDÊNCIAS      : bash, sudo, apt (curl e flatpak são instalados pelo script)
#
# CHANGELOG :
#
# 2026-10-02
# - Funções e arrays com nomes consistentes.
# - Kitty com symlinks e .desktop.
# - Incluído o AB Download Manager.
#------------------------------------------------------------------------------|

set -euo pipefail
export FLATPAK_FANCY_OUTPUT=0
trap 'printf "Falha na linha %s: %s\n" "$LINENO" "$BASH_COMMAND" >&2' ERR

#--------------------------------- VARIÁVEIS ---------------------------------->

base="https://raw.githubusercontent.com/WhoFoss/preset/refs/heads/main"
abdm_script="https://raw.githubusercontent.com/amir1376/ab-download-manager/master/scripts/install.sh"

# Cores.
verde=$'\e[1;32m'
ciano=$'\e[1;36m'
negrito=$'\e[1m'
suave=$'\e[2m'
vermelho=$'\e[1;31m'
fecha=$'\e[0m'

# Dotfiles baixados para o HOME.
declare -A dotfiles=(
    [nanorc]="${base}/files/.nanorc"
    [bashrc]="${base}/files/.bashrc"
)

# Configs do kitty.
declare -A kitty_configs=(
    [kitty.conf]="${base}/kitty/kitty.conf"
    [current-theme.conf]="${base}/kitty/current-theme.conf"
    ["Adwaita dark.conf"]="${base}/kitty/Adwaita%20dark.conf"
)

# Flatpaks (nome amigável -> id).
declare -A flatpaks=(
    [Thunderbird]="org.mozilla.thunderbird_esr"
    [KeepassXC]="org.keepassxc.KeePassXC"
    [Tuta]="com.tutanota.Tutanota"
    [Obsidian]="md.obsidian.Obsidian"
)

# Pacotes apt.
apt_pkgs=(flatpak lsd p7zip-full syncthing adb fastboot)

#------------------------------- FIM-VARIÁVEIS --------------------------------<


#----------------------------------- FUNÇÕES ---------------------------------->

# Mostra etapa de leitura.
_read() { printf "Lendo %s... %sPronto%s\n" "$*" "$verde" "$fecha"; }

# Mostra etapa de configuração.
_config() { printf "Configurando %s%s%s...\n" "$ciano" "$*" "$fecha"; }

# Mostra item sendo baixado.
_fetch() { printf "Baixar:%s%s%s %s%s%s\n" "$negrito" "$1" "$fecha" "$suave" "$2" "$fecha"; }

# Mostra item sendo instalado.
_install() { printf "Instalando %s%s%s...\n" "$ciano" "$*" "$fecha"; }

# Mostra fim do script.
_done() { printf "\n%sConcluído.%s\n" "$verde" "$fecha"; }

# Aborta com mensagem.
die() {
    printf "\n%s%s%s\n" "$vermelho" "$*" "$fecha" >&2
    exit 1
}

# Verifica em silêncio se um pacote apt está instalado.
apt_presente() {
    dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q "install ok installed"
}

# Instala só os pacotes apt que ainda faltam.
install_pkgs() {
    local faltando=()
    local pkg

    for pkg in "${apt_pkgs[@]}"; do
        if ! apt_presente "$pkg"; then
            faltando+=("$pkg")
        fi
    done

    if [[ "${#faltando[@]}" -eq 0 ]]; then
        return 0
    fi

    printf "\nOs novos pacotes a seguir serão instalados:\n%s\n\n" "${faltando[*]}"
    _read "informações de estado"
    sudo apt update
    sudo apt install -y "${faltando[@]}"
}

# Baixa dotfiles para o HOME.
get_dotfiles() {
    local i=1
    local name

    _read "listas de pacotes"
    _read "informações de estado"
    printf "\nOs novos pacotes a seguir serão instalados:\n"
    printf "%s\n" "${!dotfiles[@]}"
    printf "\n"

    for name in "${!dotfiles[@]}"; do
        _fetch "$i" ".${name}"
        curl -fsSL "${dotfiles[$name]}" -o "${HOME}/.${name}"
        i=$((i + 1))
    done
    _config "dotfiles"
}

# Baixa configs do kitty.
get_kitty_configs() {
    local i=1
    local name

    printf "\nOs novos pacotes a seguir serão instalados:\nkitty-configs\n\n"
    mkdir -p "${HOME}/.config/kitty"

    for name in "${!kitty_configs[@]}"; do
        _fetch "$i" "$name"
        curl -fsSL "${kitty_configs[$name]}" -o "${HOME}/.config/kitty/${name}"
        i=$((i + 1))
    done
    _config "kitty-configs"
}

# Instala o kitty com o instalador oficial.
kitty_install() {
    local app="${HOME}/.local/kitty.app"
    local desktop="${HOME}/.local/share/applications/kitty.desktop"

    if [[ -x "${app}/bin/kitty" ]]; then
        return 0
    fi

    printf "\n"

    printf "Instalando terminal Kitty\n\n"
    _fetch "1" "kitty (instalador oficial)"
    curl -fsSL https://sw.kovidgoyal.net/kitty/installer.sh | sh /dev/stdin launch=n

    mkdir -p "${HOME}/.local/bin" "${HOME}/.local/share/applications"
    ln -sf "${app}/bin/kitty" "${HOME}/.local/bin/kitty"
    ln -sf "${app}/bin/kitten" "${HOME}/.local/bin/kitten"
    cp "${app}/share/applications/kitty.desktop" "$desktop"
    sed -i "s|Icon=kitty|Icon=${app}/share/icons/hicolor/256x256/apps/kitty.png|g" "$desktop"
    sed -i "s|Exec=kitty|Exec=${app}/bin/kitty|g" "$desktop"
    _config "kitty"
}

# Instala só os flatpaks que ainda faltam.
flatpak_install() {
    local faltando=()
    local name

    for name in "${!flatpaks[@]}"; do
        if ! flatpak info "${flatpaks[$name]}" &>/dev/null; then
            faltando+=("$name")
        fi
    done

    if [[ "${#faltando[@]}" -eq 0 ]]; then
        return 0
    fi

    printf "\nOs novos pacotes a seguir serão instalados:\n"
    printf "  %s\n" "${faltando[@]}"
    printf "\n"

    flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo

    for name in "${faltando[@]}"; do
        _install "$name"
        flatpak install -y flathub "${flatpaks[$name]}"
    done
}

# Instala o AB Download Manager com o script oficial.
abdm_install() {
    printf "\nOs novos pacotes a seguir serão instalados:\nab-download-manager\n\n"
    _fetch "1" "ab-download-manager (script oficial)"
    bash <(curl -fsSL "$abdm_script")
    _config "ab-download-manager"
}

# Verifica se o script roda como usuário comum.
is_user() {
    if [[ "$UID" -eq 0 ]]; then
        die "Não rode como root."
    fi
}

#--------------------------------- FIM-FUNÇÕES --------------------------------<


#---------------------------------- TESTES ------------------------------------>

is_user

#--------------------------------- FIM-TESTES ---------------------------------<

# Programa começa aqui :)

clear
printf "%s=========================================%s\n" "$suave" "$fecha"
install_pkgs
get_dotfiles
get_kitty_configs
# kitty_install
flatpak_install
abdm_install
_done
