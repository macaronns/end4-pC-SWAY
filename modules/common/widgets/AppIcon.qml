import QtQuick
import Quickshell

Item {
    id: root
    
    // Propriétés de dimensionnement attendues par le reste du shell
    property real implicitSize: 26
    implicitWidth: implicitSize
    implicitHeight: implicitSize

    // Propriétés de Kirigami gardées pour éviter que les autres fichiers ne crashent
    property bool roundToIconSize: false
    property bool animated: true
    
    // Kirigami.Icon utilise la propriété 'source' pour le nom de l'icône
    property string source: ""

    Image {
        anchors.fill: parent
        // Si c'est déjà un chemin complet, on le laisse. Sinon, on demande l'icône au système via Quickshell
        source: {
            if (!root.source) return "";
            if (root.source.includes("://") || root.source.startsWith("/")) return root.source;
            return "image://icon/" + root.source;
        }
        
        sourceSize.width: root.width
        sourceSize.height: root.height
        fillMode: Image.PreserveAspectFit
        smooth: true
    }
}