#!/bin/bash
# ============================================================
#  ECLIPSE OS - gerador de ISO
#  Base: Debian 12 + Openbox + tint2 + Google Chrome
#  Rode num Debian/Ubuntu com internet:  sudo bash build-eclipse.sh
#  Resultado: ./eclipse-os/eclipse.iso  (grave com Ventoy ou Etcher)
# ============================================================
set -e
[ "$EUID" -eq 0 ] || { echo "Rode com sudo"; exit 1; }

apt-get update && apt-get install -y live-build debootstrap squashfs-tools xorriso
mkdir -p eclipse-os && cd eclipse-os
lb clean --purge 2>/dev/null || true

lb config \
  --distribution bookworm --architectures amd64 \
  --archive-areas "main contrib non-free non-free-firmware" \
  --binary-images iso-hybrid --bootloaders "syslinux,grub-efi" \
  --debian-installer none --apt-recommends false --memtest none \
  --iso-volume ECLIPSE --iso-application "Eclipse OS" --iso-publisher "Eclipse OS" \
  --bootappend-live "boot=live components quiet splash username=eclipse hostname=eclipse locales=pt_BR.UTF-8 keyboard-layouts=br timezone=America/Sao_Paulo"

# ---------- Pacotes (so o essencial) ----------
mkdir -p config/package-lists
cat > config/package-lists/eclipse.list.chroot <<'EOF'
linux-image-amd64 live-boot live-config systemd-sysv
xserver-xorg-core xserver-xorg-input-libinput xserver-xorg-video-intel xinit x11-xserver-utils
openbox obconf tint2 feh rofi lightdm lightdm-gtk-greeter
pcmanfm lxterminal lxappearance network-manager network-manager-gnome
pulseaudio pavucontrol policykit-1 udisks2 gvfs
arc-theme papirus-icon-theme fonts-noto-core fonts-noto-color-emoji
zram-tools tlp thermald intel-microcode
firmware-linux firmware-iwlwifi firmware-realtek firmware-atheros firmware-brcm80211
firmware-misc-nonfree firmware-amd-graphics firmware-intel-sound firmware-sof-signed
firmware-libertas firmware-ti-connectivity firmware-ath9k-htc
xserver-xorg-video-all xserver-xorg-input-all
bluez blueman cups usbmuxd usb-modeswitch rfkill
pciutils usbutils lshw whiptail apt-file dkms gnupg gnome-keyring
wget ca-certificates curl sudo nano jgmenu
imagemagick zenity arandr lxinput pasystray lxpolkit dbus-x11 xdg-utils
librsvg2-common gtk2-engines-murrine adwaita-icon-theme
calamares calamares-settings-debian
EOF

# ---------- Chrome pre-instalado ----------
mkdir -p config/hooks/normal
cat > config/hooks/normal/0100-chrome.hook.chroot <<'EOF'
#!/bin/bash
set -e
cd /tmp
wget -q https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
apt-get install -y ./google-chrome-stable_current_amd64.deb
rm -f google-chrome-stable_current_amd64.deb
# Claude Desktop oficial (beta Linux, repositorio apt da Anthropic)
K=/usr/share/keyrings/claude-desktop-archive-keyring.asc
if curl -fsSLo $K https://downloads.claude.ai/claude-desktop/key.asc \
   && gpg --show-keys --with-colons $K | grep -q BAA929FF1A7ECACE; then
  echo "deb [arch=amd64,arm64 signed-by=$K] https://downloads.claude.ai/claude-desktop/apt/stable stable main" > /etc/apt/sources.list.d/claude-desktop.list
  apt-get update
  apt-get install -y claude-desktop || echo "AVISO: claude-desktop nao instalou"
else
  echo "AVISO: chave da Anthropic nao confere; Claude Desktop ignorado"
fi
# Usuario eclipse (senha: eclipse), sudo sem senha e login automatico
id eclipse >/dev/null 2>&1 || useradd -m -s /bin/bash eclipse
echo "eclipse:eclipse" | chpasswd
for g in sudo audio video netdev plugdev cdrom dialout; do
  getent group $g >/dev/null && usermod -aG $g eclipse || true
done
echo "eclipse ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/eclipse
chmod 440 /etc/sudoers.d/eclipse
mkdir -p /etc/lightdm/lightdm.conf.d
printf '[Seat:*]\nautologin-user=eclipse\nautologin-user-timeout=0\nautologin-session=openbox\n' > /etc/lightdm/lightdm.conf.d/99-eclipse.conf
# Openbox usa o tema Eclipse
perl -0pi -e 's#(<theme>\s*<name>)[^<]*#${1}Eclipse#' /etc/xdg/openbox/rc.xml
# Zram (swap comprimida na RAM)
printf 'ALGO=zstd\nPERCENT=50\n' > /etc/default/zramswap
# Branding
cat > /etc/os-release <<EOT
PRETTY_NAME="Eclipse OS"
NAME="Eclipse"
ID=debian
ID_LIKE=debian
HOME_URL="https://eclipse.local"
EOT
echo "Eclipse OS" > /etc/issue
EOF
chmod +x config/hooks/normal/0100-chrome.hook.chroot

# ---------- Seletor de temas ----------
mkdir -p config/includes.chroot/usr/local/bin
cat > config/includes.chroot/usr/local/bin/eclipse-theme <<'EOF'
#!/bin/bash
# uso: eclipse-theme [preto|grafite|meia-noite|carmesim|claro]
D=$HOME/.config/eclipse; mkdir -p "$D"
T=${1:-$(cat "$D/theme" 2>/dev/null || echo preto)}
case $T in
  preto)      BG="#000000"; BG2="#0d0d0d"; FG="#e6e6e6"; ACC="#9a9a9a"; GTK=Arc-Dark;;
  grafite)    BG="#1c1c1e"; BG2="#2a2a2d"; FG="#e6e6e6"; ACC="#9aa0a6"; GTK=Arc-Dark;;
  meia-noite) BG="#0b1020"; BG2="#141b33"; FG="#dfe6ff"; ACC="#4f8cff"; GTK=Arc-Dark;;
  carmesim)   BG="#0a0000"; BG2="#1a0707"; FG="#f0dede"; ACC="#e03a3a"; GTK=Arc-Dark;;
  claro)      BG="#f2f2f2"; BG2="#ffffff"; FG="#111111"; ACC="#2563eb"; GTK=Arc;;
  *) echo "Temas: preto grafite meia-noite carmesim claro"; exit 1;;
esac
echo "$T" > "$D/theme"

# Openbox
O=$HOME/.themes/Eclipse/openbox-3; mkdir -p "$O"
cp -n /usr/share/themes/Clearlooks/openbox-3/*.xbm "$O"/ 2>/dev/null
cat > "$O/themerc" <<EOT
border.width: 1
padding.width: 6
window.client.padding.width: 0
window.*.border.color: $BG2
window.active.border.color: $ACC
window.*.title.bg: flat solid
window.*.title.bg.color: $BG2
window.inactive.title.bg.color: $BG
window.*.label.bg: parentrelative
window.*.label.text.color: $ACC
window.active.label.text.color: $FG
window.*.handle.bg: flat solid
window.*.handle.bg.color: $BG
window.*.grip.bg: flat solid
window.*.grip.bg.color: $BG
window.*.button.*.bg: parentrelative
window.*.button.*.image.color: $ACC
window.active.button.*.image.color: $FG
menu.border.color: $ACC
menu.border.width: 1
menu.items.bg: flat solid
menu.items.bg.color: $BG
menu.items.text.color: $FG
menu.items.active.bg: flat solid
menu.items.active.bg.color: $ACC
menu.items.active.text.color: $BG
menu.title.bg: flat solid
menu.title.bg.color: $BG2
menu.title.text.color: $FG
menu.separator.color: $BG2
osd.bg: flat solid
osd.bg.color: $BG
osd.label.text.color: $FG
EOT

# GTK (apps de arquivo, configuracoes etc.)
mkdir -p "$HOME/.config/gtk-3.0"
cat > "$HOME/.config/gtk-3.0/settings.ini" <<EOT
[Settings]
gtk-theme-name=$GTK
gtk-icon-theme-name=Papirus-Dark
gtk-font-name=Noto Sans 10
gtk-application-prefer-dark-theme=$([ "$T" = claro ] && echo 0 || echo 1)
EOT
cat > "$HOME/.config/gtk-3.0/gtk.css" <<EOT
window, .background, headerbar, .sidebar, treeview.view, textview text, entry, iconview {
  background-color: $BG; color: $FG; }
EOT
echo "gtk-theme-name=\"$GTK\"" > "$HOME/.gtkrc-2.0"

# Painel (tint2)
cat > "$D/tint2rc" <<EOT
rounded = 0
border_width = 0
background_color = $BG 100
border_color = $ACC 100

rounded = 0
border_width = 1
background_color = $BG2 100
border_color = $ACC 100

panel_items = LTSBC
battery_low_status = 15
battery_font_color = $FG 100
battery_padding = 6 0
panel_size = 100% 30
panel_position = bottom center horizontal
panel_background_id = 1
launcher_icon_size = 22
launcher_padding = 6 4 4
launcher_item_app = /usr/share/applications/eclipse-start.desktop
launcher_item_app = google-chrome.desktop
launcher_item_app = pcmanfm.desktop
launcher_item_app = lxterminal.desktop
taskbar_mode = single_desktop
task_text = 1
task_font_color = $FG 100
task_active_font_color = $FG 100
task_background_id = 0
task_active_background_id = 2
systray_padding = 4 2 4
time1_format = %H:%M
time1_font = Noto Sans 10
time_font_color = $FG 100
clock_padding = 8 0
EOT

# Menu Iniciar (jgmenu)
mkdir -p "$HOME/.config/jgmenu"
cat > "$HOME/.config/jgmenu/jgmenurc" <<EOT
csv_cmd = apps
position_mode = fixed
menu_halign = left
menu_valign = bottom
menu_margin_x = 0
menu_margin_y = 30
menu_width = 280
color_menu_bg = $BG 100
color_menu_border = $ACC 100
color_norm_fg = $FG 100
color_sel_bg = $ACC 100
color_sel_fg = $BG 100
color_sep_fg = $BG2 100
icon_theme = Papirus-Dark
EOT
cat > "$HOME/.config/jgmenu/append.csv" <<EOT
Configurações,eclipse-config,preferences-system
^sep()
Reiniciar,systemctl reboot,system-reboot
Desligar,systemctl poweroff,system-shutdown
Sair,openbox --exit,system-log-out
EOT

# Papel de parede (gerado, um por tema)
W="$D/wall-$T.png"
if [ ! -f "$W" ]; then
  convert -size 1920x1080 radial-gradient:"$BG2"-"$BG" \
    \( -size 1920x1080 xc:none -fill none -stroke "$ACC" -strokewidth 5 -draw "circle 960,520 960,270" -blur 0x8 \) -composite \
    \( -size 1920x1080 xc:none -fill "$BG" -stroke "$ACC" -strokewidth 2 -draw "circle 960,520 960,275" \) -composite "$W" 2>/dev/null
fi

# Area de trabalho com icones (pcmanfm)
mkdir -p "$HOME/Desktop" "$HOME/.config/pcmanfm/default" "$HOME/.config/libfm"
cp -n /usr/share/eclipse/desktop/*.desktop "$HOME/Desktop"/ 2>/dev/null
chmod +x "$HOME/Desktop"/*.desktop 2>/dev/null
printf '[config]\nquick_exec=1\n' > "$HOME/.config/libfm/libfm.conf"
cat > "$HOME/.config/pcmanfm/default/desktop-items-0.conf" <<EOT
[*]
wallpaper_mode=crop
wallpaper=$W
desktop_bg=$BG
desktop_fg=$FG
desktop_shadow=$BG
show_trash=1
show_documents=0
show_mounts=0
EOT
pkill -f "pcmanfm --desktop"; pcmanfm --desktop &
openbox --reconfigure
pkill -x tint2; tint2 -c "$D/tint2rc" &
# Icones da bandeja (Wi-Fi, som, bluetooth): reinicia junto com o painel
( sleep 2
  for a in nm-applet pasystray; do pkill -x $a; done
  pkill -f blueman-applet
  nm-applet &
  pasystray &
  blueman-applet &
  pgrep -x lxpolkit >/dev/null || lxpolkit &
) &
EOF
chmod +x config/includes.chroot/usr/local/bin/eclipse-theme

# ---------- Eclipse Drivers (detecta e instala o que faltar) ----------
cat > config/includes.chroot/usr/local/bin/eclipse-drivers <<'EOF'
#!/bin/bash
# Eclipse Drivers - procura drivers/firmware que faltam no notebook
[ "$EUID" -eq 0 ] || exec sudo "$0" "$@"
export DEBIAN_FRONTEND=noninteractive
declare -A PKG   # pacote -> motivo
add() { PKG["$1"]="$2"; }

echo "== Eclipse Drivers =="
echo "Analisando o hardware..."
PCI=$(lspci -nn 2>/dev/null); USB=$(lsusb 2>/dev/null)
FWMISS=$(dmesg 2>/dev/null | grep -iE "firmware.*(failed|not found)|direct firmware load.*failed" )

# 1) Pistas do kernel: firmware que nao foi achado
echo "$FWMISS" | grep -qiE "iwlwifi"            && add firmware-iwlwifi "Wi-Fi Intel"
echo "$FWMISS" | grep -qiE "rtl|rtw|rtlwifi"    && add firmware-realtek "Realtek (rede/Wi-Fi)"
echo "$FWMISS" | grep -qiE "ath[0-9k]|ar[0-9]{4}" && add firmware-atheros "Wi-Fi Atheros"
echo "$FWMISS" | grep -qiE "brcm|bcm"           && add firmware-brcm80211 "Wi-Fi/Bluetooth Broadcom"
echo "$FWMISS" | grep -qiE "i915|ibt|intel/"    && add firmware-misc-nonfree "Intel (video/bluetooth)"
echo "$FWMISS" | grep -qiE "amdgpu|radeon"      && add firmware-amd-graphics "Video AMD"
echo "$FWMISS" | grep -qiE "sof|snd|intel/sof"  && add firmware-sof-signed "Audio"

# 2) Pelo modelo do hardware
echo "$PCI" | grep -iE "network|ethernet" | grep -qi "broadcom" && add broadcom-sta-dkms "Wi-Fi Broadcom (driver proprietario)"
echo "$PCI" | grep -iE "network" | grep -qi "realtek" && add firmware-realtek "Realtek"
echo "$PCI" | grep -iE "vga|3d|display" | grep -qiE "amd|ati" && add firmware-amd-graphics "Video AMD"
echo "$PCI" | grep -iE "vga|3d|display" | grep -qi "nvidia" && NVIDIA=1
echo "$USB" | grep -qiE "bluetooth" && add bluez "Bluetooth"
echo "$USB" | grep -qiE "apple.*iphone|apple.*ipad" && add usbmuxd "Tethering iPhone"

# 3) Fallback: procura o arquivo de firmware no indice do Debian (precisa internet)
online() { ping -c1 -W3 deb.debian.org >/dev/null 2>&1; }
if [ -n "$FWMISS" ] && online; then
  apt-file update >/dev/null 2>&1
  for f in $(echo "$FWMISS" | grep -oE "[A-Za-z0-9_./-]+\.(bin|ucode|fw|sbcf|hex)" | sort -u); do
    p=$(apt-file search -l "$f" 2>/dev/null | grep -E "^firmware-" | head -1)
    [ -n "$p" ] && add "$p" "firmware pedido pelo kernel: $f"
  done
fi

# 4) NVIDIA: o nvidia-detect diz qual versao serve para a placa
if [ -n "$NVIDIA" ] && online; then
  apt-get install -y nvidia-detect >/dev/null 2>&1
  N=$(nvidia-detect 2>/dev/null | grep -oE "nvidia-[a-z0-9.-]*driver" | head -1)
  [ -n "$N" ] && add "$N" "Placa NVIDIA (driver recomendado)" && add linux-headers-amd64 "necessario p/ NVIDIA"
fi
[ -n "${PKG[broadcom-sta-dkms]}" ] && add linux-headers-amd64 "necessario p/ Broadcom" && add build-essential "compilar driver"

echo; echo "--- Hardware encontrado ---"
echo "$PCI" | grep -iE "vga|3d|network|ethernet|audio" | sed 's/^[^ ]* //'
echo
if [ ${#PKG[@]} -eq 0 ]; then
  echo "Nenhum driver faltando. Tudo certo!"; read -rp "Enter para fechar"; exit 0
fi
echo "--- Drivers sugeridos ---"
for k in "${!PKG[@]}"; do echo " * $k  (${PKG[$k]})"; done
echo
if ! online; then
  echo "SEM INTERNET. Conecte um cabo, ou o celular por USB (modo Tethering),"
  echo "e rode de novo:  eclipse-drivers"
  read -rp "Enter para fechar"; exit 1
fi
read -rp "Instalar agora? [S/n] " R
[[ "$R" =~ ^[nN] ]] && exit 0
apt-get update && apt-get install -y "${!PKG[@]}"
echo; echo "Concluido. Reinicie o sistema para ativar os drivers novos."
read -rp "Enter para fechar"
EOF
chmod +x config/includes.chroot/usr/local/bin/eclipse-drivers

# ---------- Eclipse IA (IA local sob demanda, nao pesa no sistema) ----------
cat > config/includes.chroot/usr/local/bin/eclipse-ia <<'EOF'
#!/bin/bash
# Eclipse IA - roda IA local (Ollama). Uso: eclipse-ia [modelo]
RAM=$(awk '/MemTotal/{printf "%d",$2/1048576}' /proc/meminfo)
if   [ "$RAM" -ge 12 ]; then M=qwen2.5:7b
elif [ "$RAM" -ge 7 ];  then M=qwen2.5:3b      # notebook de 8GB
else M=qwen2.5:1.5b; fi
M=${1:-$M}
echo "== Eclipse IA == RAM: ${RAM}GB | modelo: $M"
grep -q avx2 /proc/cpuinfo || echo "Aviso: seu processador nao tem AVX2. Funciona, mas mais devagar."
if grep -q boot=live /proc/cmdline; then
  echo "Aviso: voce esta no modo LIVE (arquivos ficam na RAM)."
  echo "Instale o Eclipse no SSD antes de baixar modelos."
  read -rp "Continuar mesmo assim? [s/N] " R; [[ "$R" =~ ^[sS] ]] || exit 0
fi
if ! command -v ollama >/dev/null; then
  ping -c1 -W3 ollama.com >/dev/null 2>&1 || { echo "Sem internet."; read -rp Enter; exit 1; }
  curl -fsSL https://ollama.com/install.sh | sh
fi
sudo systemctl start ollama 2>/dev/null
ollama run "$M"
EOF
chmod +x config/includes.chroot/usr/local/bin/eclipse-ia

# ---------- Configuracao do usuario ----------
S=config/includes.chroot/etc/xdg/openbox
mkdir -p "$S"
cat > "$S/autostart" <<'EOF'
nm-applet &
eclipse-theme &
EOF
cat > "$S/menu.xml" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<openbox_menu xmlns="http://openbox.org/3.4/menu">
<menu id="root-menu" label="Eclipse">
  <item label="Google Chrome"><action name="Execute"><command>google-chrome-stable</command></action></item>
  <item label="Arquivos"><action name="Execute"><command>pcmanfm</command></action></item>
  <item label="Terminal"><action name="Execute"><command>lxterminal</command></action></item>
  <item label="Configurações"><action name="Execute"><command>eclipse-config</command></action></item>
  <item label="Claude (app oficial)"><action name="Execute"><command>claude-desktop</command></action></item>
  <item label="IA local"><action name="Execute"><command>lxterminal -e eclipse-ia</command></action></item>
  <item label="Drivers (buscar/instalar)"><action name="Execute"><command>lxterminal -e eclipse-drivers</command></action></item>
  <item label="Buscar app"><action name="Execute"><command>rofi -show drun</command></action></item>
  <menu id="temas" label="Temas">
    <item label="Preto"><action name="Execute"><command>eclipse-theme preto</command></action></item>
    <item label="Grafite"><action name="Execute"><command>eclipse-theme grafite</command></action></item>
    <item label="Meia-noite"><action name="Execute"><command>eclipse-theme meia-noite</command></action></item>
    <item label="Carmesim"><action name="Execute"><command>eclipse-theme carmesim</command></action></item>
    <item label="Claro"><action name="Execute"><command>eclipse-theme claro</command></action></item>
  </menu>
  <separator/>
  <item label="Instalar Eclipse"><action name="Execute"><command>sudo calamares</command></action></item>
  <item label="Reiniciar"><action name="Execute"><command>systemctl reboot</command></action></item>
  <item label="Desligar"><action name="Execute"><command>systemctl poweroff</command></action></item>
  <item label="Sair"><action name="Exit"/></item>
</menu>
</openbox_menu>
EOF

# ---------- Configuracoes (estilo Windows) ----------
cat > config/includes.chroot/usr/local/bin/eclipse-config <<'EOF'
#!/bin/bash
# Configuracoes do Eclipse
while true; do
  C=$(zenity --list --title="Configurações" --width=420 --height=430 --column="Escolha" \
    "Rede e Wi-Fi" "Bluetooth" "Som" "Tela" "Aparência e temas" "Teclado e mouse" \
    "Drivers" "Atualizar o sistema" "Sobre o Eclipse") || exit 0
  case "$C" in
    "Rede e Wi-Fi") nm-connection-editor & ;;
    "Bluetooth") blueman-manager & ;;
    "Som") pavucontrol & ;;
    "Tela") arandr & ;;
    "Aparência e temas")
      T=$(zenity --list --title="Temas" --column="Tema" preto grafite meia-noite carmesim claro) && eclipse-theme "$T" ;;
    "Teclado e mouse") lxinput & ;;
    "Drivers") lxterminal -e eclipse-drivers & ;;
    "Atualizar o sistema") lxterminal -e bash -c 'sudo apt-get update && sudo apt-get -y upgrade; read -rp "Enter para fechar"' & ;;
    "Sobre o Eclipse") zenity --info --title="Eclipse OS" --text="Eclipse OS\nBase: Debian 12\nRAM em uso: $(free -h | awk '/Mem/{print $3}')" ;;
  esac
done
EOF
chmod +x config/includes.chroot/usr/local/bin/eclipse-config

# ---------- Botao Iniciar e icones da area de trabalho ----------
mkdir -p config/includes.chroot/usr/share/applications
cat > config/includes.chroot/usr/share/applications/eclipse-start.desktop <<'EOF'
[Desktop Entry]
Type=Application
Name=Iniciar
Exec=jgmenu_run
Icon=start-here
Terminal=false
EOF
DD=config/includes.chroot/usr/share/eclipse/desktop; mkdir -p "$DD"
mk() { printf '[Desktop Entry]\nType=Application\nName=%s\nExec=%s\nIcon=%s\nTerminal=false\n' "$1" "$2" "$3" > "$DD/$4.desktop"; }
mk "Google Chrome" google-chrome-stable google-chrome 1-chrome
mk "Arquivos" pcmanfm system-file-manager 2-arquivos
mk "Terminal" lxterminal utilities-terminal 3-terminal
mk "Claude" claude-desktop applications-internet 4-claude
mk "IA local" "lxterminal -e eclipse-ia" applications-science 5-ia
mk "Drivers" "lxterminal -e eclipse-drivers" preferences-system 6-drivers
mk "Configurações" eclipse-config preferences-desktop 7-config

echo ">>> Construindo a ISO (pode levar 30-60 min)..."
lb build
mv live-image-amd64.hybrid.iso eclipse.iso
echo ">>> Pronto: $(pwd)/eclipse.iso"
