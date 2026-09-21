#!/usr/bin/env bash
set -euo pipefail
trap 'echo "ERRO na linha $LINENO: $BASH_COMMAND" >&2' ERR

# --- cores (ANSI-C quoting $'...')
G=$'\e[1;32m'   # verde
Y=$'\e[1;33m'   # amarelo
C=$'\e[1;36m'   # ciano
B=$'\e[1m'      # bold
D=$'\e[2m'      # dim
R=$'\e[1;31m'   # vermelho
N=$'\e[0m'      # reset

# --- helpers de output (estilo APT)
apt_read()    { printf "Lendo %s... ${G}Pronto${N}\n" "$*"; }
apt_config()  { printf "Configurando ${C}%s${N}...\n" "$*"; }
apt_fetch()   { printf "Baixar:${B}%s${N} ${D}%s${N}\n" "$1" "$2"; }
apt_install() { printf "Instalando ${C}%s${N}... ${G}[ok]${N}\n" "$*"; }
apt_skip()    { printf "${D}%s já instalado, pulando${N}\n" "$*"; }
apt_done()    { printf "\n${G}✔ Concluído.${N}\n"; }

# --- dotfiles
declare -A dotfiles=(
  [nanorc]=https://raw.githubusercontent.com/WhoFoss/preset/refs/heads/main/files/.nanorc
  [bashrc]=https://raw.githubusercontent.com/WhoFoss/preset/refs/heads/main/files/.bashrc
)

# --- kitty configs
declare -A kitty_configs=(
  [kitty.conf]=https://raw.githubusercontent.com/WhoFoss/preset/refs/heads/main/kitty/kitty.conf
  [current-theme.conf]=https://raw.githubusercontent.com/WhoFoss/preset/refs/heads/main/kitty/current-theme.conf
  ["Adwaita dark.conf"]=https://raw.githubusercontent.com/WhoFoss/preset/refs/heads/main/kitty/Adwaita%20dark.conf
)

# --- flatpaks
declare -A flatpaks=(
  [Firefox]=org.mozilla.firefox
  [Thunderbird]=org.mozilla.thunderbird_esr
  [KeepassXC]=org.keepassxc.KeePassXC
  [Joplin]=net.cozic.joplin_desktop
  [Tuta]=com.tutanota.Tutanota
)

# --- pacotes apt
apt_pkgs=(lsd unrar p7zip-full syncthing)

# --- helpers
die() { printf '\n%sERRO: %s%s\n' "$R" "$*" "$N" >&2; exit 1; }

get_dotfiles() {
  apt_read "listas de pacotes"
  apt_read "informações de estado"
  echo
  echo "Os novos pacotes a seguir serão instalados:"
  for name in "${!dotfiles[@]}"; do
    echo "$name"
  done
  echo
  local i=1
  for name in "${!dotfiles[@]}"; do
    apt_fetch "$i" ".$name"
    curl -fsSL "${dotfiles[$name]}" -o "$HOME/.$name"
    ((i++))
  done
  apt_config "dotfiles"
}

get_kitty_configs() {
  echo
  echo "Os novos pacotes a seguir serão instalados:"
  echo "kitty-configs"
  echo
  mkdir -p "$HOME/.config/kitty"
  local i=1
  for name in "${!kitty_configs[@]}"; do
    apt_fetch "$i" "$name"
    curl -fsSL "${kitty_configs[$name]}" -o "$HOME/.config/kitty/$name"
    ((i++))
  done
  apt_config "kitty-configs"
}

kitty_install() {
  echo
  echo "Os novos pacotes a seguir serão instalados:"
  echo "kitty"
  echo
  apt_fetch "1" "kitty (installer oficial)"
  yes | bash <(curl -fsSL https://sw.kovidgoyal.net/kitty/installer.sh) || true
  apt_config "kitty"
}

flatpak_install() {
  echo
  echo "Pacotes já instalados (serão pulados):"
  for name in "${!flatpaks[@]}"; do
    id="${flatpaks[$name]}"
    flatpak info "$id" &>/dev/null && apt_skip "$name"
  done

  echo
  echo "Os novos pacotes a seguir serão instalados:"
  for name in "${!flatpaks[@]}"; do
    id="${flatpaks[$name]}"
    flatpak info "$id" &>/dev/null || echo "  $name"
  done
  echo

  flatpak remotes | grep -qw flathub \
    || flatpak remote-add flathub https://dl.flathub.org/repo/flathub.flatpakrepo

  for name in "${!flatpaks[@]}"; do
    id="${flatpaks[$name]}"
    flatpak info "$id" &>/dev/null && continue
    apt_install "$name"
    flatpak install "$id" -y
  done
}

apt_install_pkgs() {
  echo
  echo "Os novos pacotes a seguir serão instalados:"
  echo "${apt_pkgs[*]}"
  echo
  apt_read "informações de estado"
  sudo apt update
  for pkg in "${apt_pkgs[@]}"; do
    apt_install "$pkg"
    sudo apt install -y "$pkg"
  done
}

# --- main
[[ $UID -eq 0 ]] && die "não rode como root"

clear
printf "${D}=========================================${N}\n"
get_dotfiles
get_kitty_configs
kitty_install
flatpak_install
apt_install_pkgs
apt_done
