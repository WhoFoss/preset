#!/usr/bin/env bash

set -Eeuo pipefail
export FLATPAK_FANCY_OUTPUT=0
trap 'printf "Falha na linha %s: %s\n" "$LINENO" "$BASH_COMMAND" >&2' ERR

#--------------------------------- VARIÁVEIS ---------------------------------->

base="https://raw.githubusercontent.com/WhoFoss/preset/refs/heads/main"
abdm_script="https://raw.githubusercontent.com/amir1376/ab-download-manager/master/scripts/install.sh"
gtk_css="${base}/.config/gtk-3.0/gtk.css"

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
    "papirus-icon-theme|"
    "firefox|firefox firefox-esr"
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

    mkdir -p "$(dirname "$destino")"

    tmp=$(mktemp)
    if ! curl -fsSL "$url" -o "$tmp"; then
        rm -f "$tmp"
        die "Falha ao baixar: ${url}"
    fi

    mv "$tmp" "$destino"
    chmod 644 "$destino"
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
    sudo apt update && sudo apt install -y "${faltando[@]}"
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

    for name in "${!kitty_configs[@]}"; do
        baixar "${kitty_configs[$name]}" "${HOME}/.config/kitty/${name}"
    done
}

# Baixa o gtk.css do painel do XFCE.
get_gtk_css() {
    baixar "$gtk_css" "${HOME}/.config/gtk-3.0/gtk.css"
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

    sudo flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo

    for name in "${faltando[@]}"; do
        _install "$name"
        sudo flatpak install -y flathub "${flatpaks[$name]}"
    done
}

# Instala o fastfetch (apt; se não existir no repositório, usa o .deb do GitHub).
fastfetch_install() {
    local url="https://github.com/fastfetch-cli/fastfetch/releases/latest/download/fastfetch-linux-amd64.deb"
    local tmp

    if detectar "fastfetch" fastfetch; then
        return 0
    fi

    printf "\n"
    _install "fastfetch"

    if apt-cache show fastfetch &>/dev/null; then
        sudo apt install -y fastfetch
        return 0
    fi

    tmp=$(mktemp --suffix=.deb)

    if ! curl -fsSL "$url" -o "$tmp"; then
        rm -f "$tmp"
        die "Falha ao baixar: ${url}"
    fi

    chmod 644 "$tmp"
    sudo apt install -y "$tmp"
    rm -f "$tmp"
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

# Instala a JetBrainsMono Nerd Font em ~/.local/share/fonts.
fonte_instalar() {
    local dir="${HOME}/.local/share/fonts/JetBrainsMonoNerd"
    local url="https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip"
    local tmp

    if [[ -d "$dir" ]]; then
        return 0
    fi

    printf "\n"
    _install "JetBrainsMono Nerd Font"
    tmp=$(mktemp --suffix=.zip)

    if ! curl -fsSL "$url" -o "$tmp"; then
        rm -f "$tmp"
        die "Falha ao baixar: ${url}"
    fi

    mkdir -p "$dir"
    unzip -qo "$tmp" -d "$dir"
    rm -f "$tmp"
    fc-cache -f "$dir"
    _config "fonte JetBrainsMono Nerd Font"
}

# Define a Nerd Font como fonte do xfce4-terminal.
fonte_terminal() {
    local fonte="JetBrainsMono Nerd Font Mono 10"
    local rc="${HOME}/.config/xfce4/terminal/terminalrc"

    command -v xfce4-terminal &>/dev/null || return 0
    mkdir -p "$(dirname "$rc")"

    if [[ ! -f "$rc" ]]; then
        printf "[Configuration]\nFontUseSystem=FALSE\nFontName=%s\n" "$fonte" > "$rc"
    elif grep -q "^FontName=${fonte}$" "$rc"; then
        return 0
    else
        sed -i '/^FontName=/d;/^FontUseSystem=/d' "$rc"
        sed -i "/^\[Configuration\]/a FontUseSystem=FALSE\nFontName=${fonte}" "$rc"
    fi

    _config "fonte do xfce4-terminal"
}

# Aplica o tema de ícones Papirus-Dark no XFCE.
icones_aplicar() {
    local tema="Papirus-Dark"
    local bus atual

    command -v xfconf-query &>/dev/null || return 0
    if [[ ! -d "/usr/share/icons/${tema}" && ! -d "${HOME}/.icons/${tema}" && ! -d "${HOME}/.local/share/icons/${tema}" ]]; then
        return 0
    fi

    if [[ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ]]; then
        bus="/run/user/${UID}/bus"
        if [[ ! -S "$bus" ]]; then
            printf "Ícones %s: sessão gráfica não encontrada; aplique depois.\n" "$tema"
            return 0
        fi
        export DBUS_SESSION_BUS_ADDRESS="unix:path=${bus}"
    fi

    atual=$(xfconf-query -c xsettings -p /Net/IconThemeName 2>/dev/null || true)

    if [[ "$atual" == "$tema" ]]; then
        return 0
    fi

    xfconf-query -c xsettings -p /Net/IconThemeName --create -t string -s "$tema"
    _config "ícones ${tema}"
}

# Verifica se o script roda como usuário comum e se o sudo existe.
nao_root() {
    if [[ "$UID" -eq 0 ]]; then
        die "Não rode como root; rode como usuário comum (o sudo é pedido quando preciso)."
    fi

    if ! command -v sudo &>/dev/null; then
        die "sudo não encontrado."
    fi
}

#--------------------------------- FIM-FUNÇÕES --------------------------------<


#---------------------------------- TESTES ------------------------------------>

nao_root

#--------------------------------- FIM-TESTES ---------------------------------<

# Programa começa aqui :)

# Limpa a tela só se a saída for um terminal.
if [[ -t 1 ]]; then
    tput clear
fi
printf "%s=========================================%s\n" "$suave" "$fecha"
install_pkgs
fastfetch_install
fonte_instalar
fonte_terminal
get_dotfiles
get_kitty_configs
get_gtk_css
icones_aplicar
# kitty_install
flatpak_install
abdm_install
_done
