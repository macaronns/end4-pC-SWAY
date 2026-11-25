{
  description = "Environnement de développement pour end4-pC (Quickshell / QML)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs, ... }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
    in
    {
      devShells.${system}.default = pkgs.mkShell {
        # nativeBuildInputs charge les outils et les hooks (comme wrapQtAppsHook)
        nativeBuildInputs = with pkgs; [
          qt6.wrapQtAppsHook
          prettier
        ];

        # buildInputs charge les librairies partagées que Qt devra trouver
        buildInputs = with pkgs; [
          # --- Moteur et UI ---
          quickshell
          qt6.qtwayland
          qt6.qtdeclarative
          qt6.qtsvg
          qt6.qt5compat
          qt6.qtpositioning
	  qt6.qtbase          # NOUVEAU: Contient setupQtEnvironment
          qt6.qt5compat       # C'est lui qui contient GraphicalEffects
          kdePackages.syntax-highlighting
          kdePackages.kirigami
          kdePackages.kirigami-addons

          # --- Outils de scripting, IPC et Génération de thème ---
          sway
          jq
          socat
          cliphist
          ddcutil
          matugen         # NOUVEAU: Générateur de thème Material You
          imagemagick     # NOUVEAU: Pour analyser l'image (commande identify)
          bc              # NOUVEAU: Pour les calculs mathématiques du script
          
          (python3.withPackages (ps: with ps; [
            i3ipc
            pillow           # NOUVEAU: Manipulation d'images
            materialyoucolor # NOUVEAU: Algorithmes Material You
          ]))
        ];

        # Variables d'environnement pour Wayland
        QT_QPA_PLATFORM = "wayland";
        QT_WAYLAND_DISABLE_WINDOWDECORATION = "1";

	# Le shellHook s'occupe de lier le tout
        shellHook = ''
          qtWrapperArgs=()
          setupQtEnvironment

	  # On ajoute syntax-highlighting aux chemins QML avec les autres modules
          export QML2_IMPORT_PATH="${pkgs.qt6.qt5compat}/lib/qt-6/qml:${pkgs.qt6.qtpositioning}/lib/qt-6/qml:${pkgs.qt6.qtdeclarative}/lib/qt-6/qml:${pkgs.kdePackages.kirigami}/lib/qt-6/qml:${pkgs.kdePackages.kirigami-addons}/lib/qt-6/qml:${pkgs.kdePackages.syntax-highlighting}/lib/qt-6/qml"
          export QML_IMPORT_PATH="$QML2_IMPORT_PATH"
          export QT_PLUGIN_PATH="${pkgs.qt6.qtbase}/lib/qt-6/plugins"

          echo "=========================================================="
          echo "  💠 Environnement de dev end4-pC chargé !"
          echo "=========================================================="
          echo " • Moteur        : Quickshell (qs)"
          echo " • LSP dispo     : qmlls (via qtdeclarative)"
          echo " • Outils ajoutés: swaymsg, jq, python-i3ipc, cliphist, ddcutil"
          echo " "
          echo " 🚀 Pour tester vos modifications, tapez :"
          echo "    qs -p ."
          echo "=========================================================="
        '';
      };
    };
}
