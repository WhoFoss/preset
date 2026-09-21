#!/usr/bin/env bash
set -euo pipefail

# --- dotfiles
declare -A dotfiles=(
  [nanorc]=https://raw.githubusercontent.com/WhoFoss/preset/refs/heads/main/files/.nanorc
  [bashrc]=https://raw.githubusercontent.com/WhoFoss/preset/refs/heads/main/files/.bashrc
)

# --- kitty configs (vão para ~/.config/kitty/)
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
apt_pkgs=(lsd unrar p7zip-full)

# --- helpers
die() { printf '\nERRO: %s\n' "$*" >&2; exit 1; }

get_dotfiles() {
  echo ":.:. dotfiles"
  for name in "${!dotfiles[@]}"; do
    echo "baixando .$name"
    curl -fsSL "${dotfiles[$name]}" -o "$HOME/.$name"
  done
}

get_kitty_configs() {
  echo ":.:. kitty configs"
  mkdir -p "$HOME/.config/kitty"
  for name in "${!kitty_configs[@]}"; do
    echo "baixando $name"
    curl -fsSL "${kitty_configs[$name]}" -o "$HOME/.config/kitty/$name"
  done
}

kitty_install() {
  echo ":.:. kitty (instalador oficial)"
  yes | bash <(curl -fsSL https://sw.kovidgoyal.net/kitty/installer.sh)
}

flatpak_install() {
  echo ":.:. flatpaks"
  flatpak remotes | grep -qw flathub \
    || flatpak remote-add flathub https://dl.flathub.org/repo/flathub.flatpakrepo

  for name in "${!flatpaks[@]}"; do
    id="${flatpaks[$name]}"
    flatpak info "$id" &>/dev/null && continue
    echo "instalando $name"
    flatpak install "$id" -y
  done
}

apt_install() {
  echo ":.:. pacotes apt"
  sudo apt update
  sudo apt install -y "${apt_pkgs[@]}"
}

# --- main
[[ $UID -eq 0 ]] && die "não rode como root"
get_dotfiles
get_kitty_configs
kitty_install
flatpak_install
apt_install
