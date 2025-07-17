# Maintainer: Your Name <spikygames123@gmail.com>
pkgname=wayterm-git
pkgver=r1.0.0
pkgrel=1
pkgdesc="A terminal emulator built with Vala, GTK4, and libadwaita"
arch=('x86_64')
url="https://github.com/Squar-DE/wayterm"
license=('GPL3')
depends=('gtk4' 'libadwaita' 'vte4' 'gdk-pixbuf2')
makedepends=('vala' 'git')
provides=('wayterm')
conflicts=('wayterm')
source=('git+file://'"$PWD")
sha256sums=('SKIP')

pkgver() {
    cd "$srcdir/wayterm"
    echo "r$(git rev-list --count HEAD).$(git rev-parse --short HEAD)"
}

build() {
    cd "$srcdir/wayterm"
    
    # Build with valac
    valac --pkg gtk4 --pkg libadwaita-1 --pkg vte-2.91-gtk4 --pkg gdk-pixbuf-2.0 main.vala -o wayterm
}

package() {
    cd "$srcdir/wayterm"
    
    # Install the binary
    install -Dm755 wayterm "$pkgdir/usr/bin/wayterm"
    
    Install desktop file if you have one
    install -Dm644 wayterm.desktop "$pkgdir/usr/share/applications/wayterm.desktop"
    
    # Install icon if you have one
    # install -Dm644 wayterm.png "$pkgdir/usr/share/pixmaps/wayterm.png"
}
