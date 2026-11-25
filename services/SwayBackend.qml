pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: root

    // Propriétés standardisées attendues par le shell
    property var windowList: []
    property var workspaces: []
    property var workspaceById: ({})
    property var activeWorkspace: null
    property var monitors: []
    property var focusedMonitor: null

    // --- ACTIONS (Envoyées à Sway) ---

    // Un processus générique et réutilisable pour envoyer des commandes sans bloquer l'UI
    Process {
        id: cmdRunner
    }

    function runCmd(args) {
        cmdRunner.command = args;
        cmdRunner.running = true;
    }

    function switchWorkspaceRelative(direction) {
        let cmd = direction === "next" ? "next_on_output" : "prev_on_output";
        runCmd(["swaymsg", "workspace", cmd]);
    }

    function focusWindow(id) {
        runCmd(["swaymsg", `[con_id=${id}]`, "focus"]);
    }
    function closeWindow(id) {
        runCmd(["swaymsg", `[con_id=${id}]`, "kill"]);
    }
    function switchWorkspace(id) {
        runCmd(["swaymsg", "workspace", "number", id.toString()]);
    }
    function moveWindowToWorkspace(id, wsId) {
        runCmd(["swaymsg", `[con_id=${id}]`, "move", "container", "to", "workspace", "number", wsId.toString()]);
    }

    // --- UTILITAIRES D'INTERFACE ---

    function normalizeWindow(w, wsId) {
        // Transforme un nœud de l'arbre Sway en format standard pour le shell
        return {
            id: w.id.toString(), // Sway utilise des ID entiers pour les nœuds
            address: w.id.toString(),
            title: w.name || "Unknown",
            appId: w.app_id || (w.window_properties ? w.window_properties.class : ""),
            workspaceId: wsId,
            focused: w.focused
        };
    }

    function monitorFor(screen) {
        return monitors.find(m => m.name === screen.name) || null;
    }

    function activeWorkspaceForMonitor(monitorName) {
        let ws = workspaces.find(w => w.monitorName === monitorName && w.visible);
        return ws ? { id: ws.id } : null;
    }

    function biggestWindowForWorkspace(wsId) {
        // Trouve la fenêtre la plus grande sur ce bureau
        let wsWindows = windowList.filter(w => w.workspaceId == wsId);
        return wsWindows.length > 0 ? wsWindows[0] : null; 
    }

    function fullscreenOnMonitor(monitorName) {
        // Simplification : nécessite une passe complexe sur l'arbre pour Sway
        return false;
    }

    function monitorGeometry(screen) {
        let m = monitorFor(screen);
        if (!m) return { x: 0, y: 0, scale: 1 };
        return { x: m.rect.x, y: m.rect.y, scale: m.scale };
    }

    // --- MOTEUR DE RAFRAÎCHISSEMENT (Lecture de l'état Sway) ---

    // 1. Processus qui fetch l'état complet en un coup (Workspaces + Outputs + Tree)
    Process {
        id: swayStateFetcher
        // On demande à Sway de sortir du JSON brut, et jq -c le met sur une seule ligne.
        command: ["sh", "-c", "swaymsg -t get_workspaces -r | jq -c '.'; swaymsg -t get_outputs -r | jq -c '.'; swaymsg -t get_tree -r | jq -c '.'"]
        
        stdout: SplitParser {
            property int index: 0
            property string wsData: ""
            property string outData: ""

            onRead: data => {
                // On ignore les lignes vides potentielles
                if (data.trim() === "") return;

                if (index === 0) { 
                    wsData = data; 
                } else if (index === 1) { 
                    outData = data; 
                } else if (index === 2) { 
                    parseState(wsData, outData, data); // Le 3ème data est l'arbre
                    index = 0; // Reset pour le prochain rafraîchissement
                    return;
                }
                index++;
            }
        }
    }

    // Fonction qui parse le JSON brut de Sway et met à jour les variables du shell
    function parseState(wsRaw, outRaw, treeRaw) {
        try {
            let wsJson = JSON.parse(wsRaw);
            let outJson = JSON.parse(outRaw);
            let treeJson = JSON.parse(treeRaw);

            // A. Monitors
            monitors = outJson.map(o => ({
                id: o.id,
                name: o.name,
                rect: o.rect,
                scale: o.scale || 1
            }));

            // B. Workspaces
            let newWsById = {};
            let newActiveWs = null;
            let formattedWorkspaces = wsJson.map(w => {
                let normWs = {
                    id: w.num,
                    name: w.name,
                    active: w.focused,
                    visible: w.visible,
                    monitorName: w.output
                };
                newWsById[normWs.id] = normWs;
                if (w.focused) newActiveWs = normWs;
                return normWs;
            });

            // C. Windows (Lecture récursive de l'arbre Sway)
            let newWindowList = [];
            function traverseTree(node, currentWsId) {
                let wsId = currentWsId;
                
                // Si on entre dans un nœud Workspace, on garde son ID
                if (node.type === "workspace" && node.num !== -1) {
                    wsId = node.num;
                }
                
                // Si c'est une vraie fenêtre d'application
                if (node.type === "con" || node.type === "floating_con") {
                    if (node.name && (node.app_id || node.window_properties)) {
                        newWindowList.push(normalizeWindow(node, wsId));
                    }
                }
                
                // On descend dans les enfants
                if (node.nodes) node.nodes.forEach(n => traverseTree(n, wsId));
                if (node.floating_nodes) node.floating_nodes.forEach(n => traverseTree(n, wsId));
            }
            traverseTree(treeJson, -1);

            // D. Mise à jour finale (pour déclencher les signaux QML en une seule fois)
            workspaceById = newWsById;
            workspaces = formattedWorkspaces;
            activeWorkspace = newActiveWs;
            windowList = newWindowList;
            
            // Met à jour le moniteur focalisé
            if (newActiveWs) {
                focusedMonitor = monitors.find(m => m.name === newActiveWs.monitorName) || null;
            }

        } catch (e) {
            console.log("[SwayBackend] Erreur de parsing JSON :", e);
        }
    }

    // 2. Processus qui écoute les événements en boucle
    Process {
        id: swayListener
        command: ["swaymsg", "-t", "subscribe", "-m", "[\"workspace\", \"window\", \"output\"]"]
        running: true // Tourne à l'infini
        stdout: SplitParser {
            onRead: data => {
                // Dès que Sway signale un changement, on relance le fetcher
                swayStateFetcher.running = true;
            }
        }
    }

    // 3. Au démarrage, on fetch l'état initial
    Component.onCompleted: {
        swayStateFetcher.running = true;
    }
}