#!/usr/bin/env bash

set -Eeuo pipefail
export FLATPAK_FANCY_OUTPUT=0
trap 'printf "Falha na linha %s: %s\n" "$LINENO" "$BASH_COMMAND" >&2' ERR

#--------------------------------- VARIÁVEIS ---------------------------------->

base="https://raw.githubusercontent.com/WhoFoss/preset/refs/heads/main"
abdm_script="https://raw.githubusercontent.com/amir1376/ab-download-manager/master/scripts/install.sh"

# Usuário que recebe as configs (quem chamou o sudo; sem sudo, o próprio root).
usuario_alvo="${SUDO_USER:-root}"
home_alvo=$(getent passwd "$usuario_alvo" | cut -d: -f6 || true)
export HOME="$home_alvo"

# Cores e estilos (tput).
negrito=$(tput bold 2>/dev/null || true)
suave=$(tput dim 2>/dev/null || true)
verde="${negrito}$(tput setaf 2 2>/dev/null || true)"
ciano="${negrito}$(tput setaf 6 2>/dev/null || true)"
vermelho="${negrito}$(tput setaf 1 2>/dev/null || true)"
fecha=$(tput sgr0 2>/dev/null || true)

# Pastas onde ficam os atalhos .desktop (nativo, flatpak e snap).
dirs_desktop=(
    /usr/share/applications
    "${HOME}/.local/share/applications"
    /var/lib/flatpak/exports/share/applications
    "${HOME}/.local/share/flatpak/exports/share/applications"
    /var/lib/snapd/desktop/applications
)

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

# Pacotes apt (pacote|comandos que indicam que já existe).
apt_pkgs=(
    "flatpak|flatpak"
    "lsd|lsd"
    "p7zip-full|7z 7za 7zz"
    "syncthing|syncthing"
    "adb|adb"
    "fastboot|fastboot"
)

# Detecção dos flatpaks (nome amigável -> padrão|comandos possíveis).
declare -A flatpaks_detect=(
    [Thunderbird]="thunderbird|thunderbird"
    [KeepassXC]="keepassxc|keepassxc"
    [Tuta]="tutanota|tutanota-desktop tutanota"
    [Obsidian]="obsidian|obsidian"
)

#------------------------------- FIM-VARIÁVEIS --------------------------------<


#----------------------------------- FUNÇÕES ---------------------------------->

# Mostra item sendo baixado.
_fetch() { printf "Baixar:%s%s%s %s%s%s\n" "$negrito" "$1" "$fecha" "$suave" "$2" "$fecha"; }

# Mostra item sendo instalado.
_install() { printf "Instalando %s%s%s...\n" "$ciano" "$*" "$fecha"; }

# Mostra etapa de configuração.
_config() { printf "Configurando %s%s%s...\n" "$ciano" "$*" "$fecha"; }

# Mostra fim do script.
_done() { printf "\n%sConcluído.%s\n" "$verde" "$fecha"; }

# Aborta com mensagem.
die() {
    printf "\n%s%s%s\n" "$vermelho" "$*" "$fecha" >&2
    exit 1
}

# Cria a pasta (e as que faltarem no caminho) com o usuário alvo como dono.
mkdir_dono() {
    local alvo="$1"
    local rel="${alvo#"${home_alvo}"/}"
    local atual="$home_alvo"
    local parte
    local IFS=/

    for parte in $rel; do
        atual="${atual}/${parte}"
        if [[ ! -d "$atual" ]]; then
            mkdir "$atual"
            chown "${usuario_alvo}:" "$atual"
        fi
    done
}

# Procura os comandos no PATH e em ~/.local/bin.
achou_cmd() {
    local c

    for c in "$@"; do
        if command -v "$c" &>/dev/null || [[ -x "${HOME}/.local/bin/${c}" ]]; then
            return 0
        fi
    done
    return 1
}

# Procura um atalho .desktop cujo nome contém o texto.
achou_desktop() {
    local achado

    achado=$(find "${dirs_desktop[@]}" -maxdepth 1 -iname "*${1}*.desktop" -print -quit 2>/dev/null || true)
    [[ -n "$achado" ]]
}

# Procura um flatpak cujo ID contém o texto.
achou_flatpak() {
    local lista

    command -v flatpak &>/dev/null || return 1
    lista=$(flatpak list --app --columns=application 2>/dev/null || true)
    [[ "${lista,,}" == *"${1,,}"* ]]
}

# Procura um pacote apt instalado com esse nome exato.
achou_apt() {
    local estado

    estado=$(dpkg-query -W -f='${db:Status-Abbrev}' "$1" 2>/dev/null || true)
    [[ "$estado" == ii* ]]
}

# Procura um snap cujo nome contém o texto.
achou_snap() {
    local lista

    command -v snap &>/dev/null || return 1
    lista=$(snap list 2>/dev/null || true)
    [[ "${lista,,}" == *"${1,,}"* ]]
}

# Detecta em silêncio se um programa já existe (padrão + comandos possíveis).
detectar() {
    local padrao="$1"
    shift

    achou_cmd "$@" && return 0
    achou_desktop "$padrao" && return 0
    achou_flatpak "$padrao" && return 0
    achou_apt "$padrao" && return 0
    achou_snap "$padrao" && return 0
    return 1
}

# Baixa um arquivo só se o destino ainda não existir.
baixar() {
    local url="$1"
    local destino="$2"
    local tmp

    if [[ -e "$destino" ]]; then
        return 0
    fi

    tmp=$(mktemp)
    if ! curl -fsSL "$url" -o "$tmp"; then
        rm -f "$tmp"
        die "Falha ao baixar: ${url}"
    fi

    mv "$tmp" "$destino"
    chmod 644 "$destino"
    chown "${usuario_alvo}:" "$destino"
    _fetch "$(basename "$destino")" "baixado"
}

# Instala só os pacotes apt que ainda faltam (por comando ou pacote).
install_pkgs() {
    local faltando=()
    local item pkg cmds

    for item in "${apt_pkgs[@]}"; do
        pkg="${item%%|*}"
        cmds="${item#*|}"
        # shellcheck disable=SC2086
        if ! detectar "$pkg" $cmds; then
            faltando+=("$pkg")
        fi
    done

    if [[ "${#faltando[@]}" -eq 0 ]]; then
        return 0
    fi

    printf "\nOs novos pacotes a seguir serão instalados:\n%s\n\n" "${faltando[*]}"
    apt update && apt install -y "${faltando[@]}"
}

# Baixa dotfiles para o HOME.
get_dotfiles() {
    local name

    for name in "${!dotfiles[@]}"; do
        baixar "${dotfiles[$name]}" "${HOME}/.${name}"
    done
}

# Baixa configs do kitty.
get_kitty_configs() {
    local name

    mkdir_dono "${HOME}/.config/kitty"

    for name in "${!kitty_configs[@]}"; do
        baixar "${kitty_configs[$name]}" "${HOME}/.config/kitty/${name}"
    done
}

# Instala o kitty com o instalador oficial, se ainda não existir.
kitty_install() {
    local app="${HOME}/.local/kitty.app"
    local desktop="${HOME}/.local/share/applications/kitty.desktop"

    if detectar "kitty" kitty; then
        return 0
    fi

    printf "\n"
    _install "Kitty"
    mkdir_dono "${HOME}/.local"
    curl -fsSL https://sw.kovidgoyal.net/kitty/installer.sh | sh /dev/stdin launch=n

    mkdir_dono "${HOME}/.local/bin"
    mkdir_dono "${HOME}/.local/share/applications"
    ln -sf "${app}/bin/kitty" "${HOME}/.local/bin/kitty"
    ln -sf "${app}/bin/kitten" "${HOME}/.local/bin/kitten"
    cp "${app}/share/applications/kitty.desktop" "$desktop"
    sed -i "s|Icon=kitty|Icon=${app}/share/icons/hicolor/256x256/apps/kitty.png|g" "$desktop"
    sed -i "s|Exec=kitty|Exec=${app}/bin/kitty|g" "$desktop"

    chown -R "${usuario_alvo}:" "$app"
    chown -h "${usuario_alvo}:" "${HOME}/.local/bin/kitty" "${HOME}/.local/bin/kitten"
    chown "${usuario_alvo}:" "$desktop"
    _config "kitty"
}

# Instala só os flatpaks que ainda faltam.
flatpak_install() {
    local faltando=()
    local name item padrao cmds

    for name in "${!flatpaks[@]}"; do
        item="${flatpaks_detect[$name]}"
        padrao="${item%%|*}"
        cmds="${item#*|}"
        # shellcheck disable=SC2086
        if ! detectar "$padrao" $cmds; then
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

# Instala o AB Download Manager com o script oficial, se ainda não existir.
abdm_install() {
    if detectar "abdownload" ABDownloadManager abdownloadmanager; then
        return 0
    fi

    printf "\n"
    _install "AB Download Manager"
    bash <(curl -fsSL "$abdm_script")
    _config "ab-download-manager"
}

# Verifica se o script roda como root.
is_root() {
    if [[ "$UID" -ne 0 ]]; then
        die "Rode como root."
    fi

    if [[ -z "$home_alvo" || ! -d "$home_alvo" ]]; then
        die "Home do usuário '${usuario_alvo}' não encontrado."
    fi
}

#--------------------------------- FIM-FUNÇÕES --------------------------------<


#---------------------------------- TESTES ------------------------------------>

is_root

#--------------------------------- FIM-TESTES ---------------------------------<

# Programa começa aqui :)

# Limpa a tela só se a saída for um terminal.
if [[ -t 1 ]]; then
    tput clear
fi
printf "%s=========================================%s\n" "$suave" "$fecha"
install_pkgs
get_dotfiles
get_kitty_configs
# kitty_install
flatpak_install
abdm_install
_done
