#!/usr/bin/env bash
# Post-rootfs hook for Titanoboa: turns Sivablue's bootc rootfs into a
# Live-bootable installer environment (GNOME live session + Anaconda Live).

set -eoux pipefail

# Titanoboa exports IMAGE_REF / IMAGE_TAG. Fall back to image-info.json if present.
if [[ -z "${IMAGE_REF:-}" || -z "${IMAGE_TAG:-}" ]]; then
    if [[ -f /usr/share/ublue-os/image-info.json ]]; then
        IMAGE_INFO="$(cat /usr/share/ublue-os/image-info.json)"
        IMAGE_TAG="$(jq -c -r '."image-tag"' <<<"$IMAGE_INFO")"
        IMAGE_REF="$(jq -c -r '."image-ref"' <<<"$IMAGE_INFO")"
    fi
fi
IMAGE_REF="${IMAGE_REF##*://}"

safe_disable() {
    local unit="$1"
    if systemctl list-unit-files | grep -q "^${unit}\b"; then
        systemctl disable "$unit" || true
    fi
}
safe_disable_global() {
    local unit="$1"
    if systemctl --global list-unit-files | grep -q "^${unit}\b"; then
        systemctl --global disable "$unit" || true
    fi
}

############################################
# Live GNOME environment
############################################

tee /usr/share/glib-2.0/schemas/zz2-org.gnome.shell.gschema.override <<EOF
[org.gnome.shell]
welcome-dialog-last-shown-version='4294967295'
favorite-apps = ['anaconda.desktop', 'org.gnome.Ptyxis.desktop', 'net.waterfox.waterfox.desktop', 'org.gnome.Nautilus.desktop', 'io.github.kolunmi.Bazaar.desktop', 'code.desktop']
EOF

tee /usr/share/glib-2.0/schemas/zz3-sivablue-installer-power.gschema.override <<EOF
[org.gnome.settings-daemon.plugins.power]
sleep-inactive-ac-type='nothing'
sleep-inactive-battery-type='nothing'
sleep-inactive-ac-timeout=0
sleep-inactive-battery-timeout=0

[org.gnome.desktop.session]
idle-delay=uint32 0
EOF

rm -f /etc/xdg/autostart/org.gnome.Software.desktop

tee /usr/share/gnome-shell/search-providers/org.gnome.Software-search-provider.ini <<EOF
DefaultDisabled=true
EOF

glib-compile-schemas /usr/share/glib-2.0/schemas

# Services that belong on the *installed* system, not the live ISO.
# Cross-referenced against Sivablue/build/25-sysconfig.sh and
# Sivablue/system/usr/lib/systemd/.
for u in \
    rpm-ostree-countme.timer \
    rpm-ostreed-automatic.timer \
    flatpak-preinstall.service \
    flatpak-nuke-fedora.service \
    set-hostname.service \
    auto-groups.service \
    brew-setup.service \
    brew-update.timer \
    brew-upgrade.timer \
    uupd.timer \
    tailscaled.service \
    tailscale-operator.service ; do
    safe_disable "$u"
done
for u in \
    podman-auto-update.timer \
    sivablue-user-setup.service ; do
    safe_disable_global "$u"
done

# https://bugzilla.redhat.com/show_bug.cgi?id=2433186
if rpm -q generic-logos &>/dev/null; then
    rpm --erase --nodeps --justdb generic-logos
    dnf download fedora-logos
    rpm -i --justdb fedora-logos*.rpm
    rm -f fedora-logos*.rpm
fi

############################################
# Anaconda Live installer
############################################

dnf install -y \
    libblockdev-btrfs \
    libblockdev-lvm \
    libblockdev-dm \
    anaconda-live \
    firefox  # required by anaconda-webui (renders the installer UI in a browser kiosk)

tee /etc/anaconda/profile.d/sivablue.conf <<'EOF'
# Anaconda configuration file for Sivablue

[Profile]
profile_id = sivablue

[Profile Detection]
os_id = sivablue

[Network]
default_on_boot = FIRST_WIRED_WITH_LINK

[Bootloader]
efi_dir = fedora
menu_auto_hide = True

[Storage]
default_scheme = BTRFS
btrfs_compression = zstd:1
default_partitioning =
    /     (min 1 GiB, max 70 GiB)
    /home (min 500 MiB, free 50 GiB)
    /var  (btrfs)

[User Interface]
hidden_spokes =
    NetworkSpoke
    PasswordSpoke
    UserSpoke
hidden_webui_pages =
    anaconda-screen-accounts

[Localization]
use_geolocation = False
EOF

# Make Anaconda Profile Detection match. Sivablue inherits silverblue's os-release,
# so override ID to "sivablue" so the profile picks up.
sed -i 's/^ID=.*/ID=sivablue/' /usr/lib/os-release
grep -q '^VARIANT_ID=sivablue' /usr/lib/os-release || echo "VARIANT_ID=sivablue" >>/usr/lib/os-release

. /etc/os-release
echo "Sivablue release ${VERSION_ID:-unknown} (${VERSION_CODENAME:-})" >/etc/system-release

sed -i 's/ANACONDA_PRODUCTVERSION=.*/ANACONDA_PRODUCTVERSION=""/' /usr/{,s}bin/liveinst || true
sed -i 's| Fedora| Sivablue|' /usr/share/anaconda/gnome/fedora-welcome || true
sed -i 's|Activities|in the dock|' /usr/share/anaconda/gnome/fedora-welcome || true
sed -i -e "s/Fedora/Sivablue/g" -e "s/CentOS/Sivablue/g" \
    /usr/share/anaconda/gnome/org.fedoraproject.welcome-screen.desktop || true

############################################
# Interactive kickstart
############################################

tee -a /usr/share/anaconda/interactive-defaults.ks <<EOF
ostreecontainer --url=$IMAGE_REF:$IMAGE_TAG --transport=containers-storage --no-signature-verification
%include /usr/share/anaconda/post-scripts/install-configure-upgrade.ks
%include /usr/share/anaconda/post-scripts/disable-fedora-flatpak.ks
%include /usr/share/anaconda/post-scripts/install-flatpaks.ks
EOF

tee /usr/share/anaconda/post-scripts/install-configure-upgrade.ks <<EOF
%post --erroronfail
bootc switch --mutate-in-place --transport registry $IMAGE_REF:$IMAGE_TAG
%end
EOF

tee /usr/share/anaconda/post-scripts/disable-fedora-flatpak.ks <<'EOF'
%post --erroronfail
systemctl disable flatpak-add-fedora-repos.service || true
%end
EOF

tee /usr/share/anaconda/post-scripts/install-flatpaks.ks <<'EOF'
%post --erroronfail --nochroot
deployment="$(ostree rev-parse --repo=/mnt/sysimage/ostree/repo ostree/0/1/0)"
target="/mnt/sysimage/ostree/deploy/default/deploy/$deployment.0/var/lib/"
mkdir -p "$target"
rsync -aAXUHKP /var/lib/flatpak "$target"
%end
EOF
