// SPDX-License-Identifier: GPL-3.0-only
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs
import "ReviewDocument.js" as Review

Item {
    id: root
    required property var view
    property var document: Review.empty("")
    property string contextId: ""
    property string recoveryUrl: ""
    property string savedUrl: ""
    property bool dirty: false
    property bool showMarks: true
    property string tool: "pen"
    property var draft: null
    property var draftGeometry: null
    property var textGeometry: null
    property var textScorePoint: null
    property string relocatingId: ""
    property var history: []
    property var future: []
    property var resolved: []
    property string error: ""
    property var contextCache: ({})
    readonly property bool active: view.reviewActive
    readonly property int orphanCount: resolved.filter(function(r) { return !r.geometry.valid }).length

    function persistRecovery() {
        if (!contextId || !recoveryUrl) return
        if (!view.saveReview(recoveryUrl, JSON.stringify(document)))
            error = qsTr("Recupero automatico non riuscito. Salva la revisione in un file.")
    }
    function switchContext() {
        var nextId = view.reviewScoreId
        if (nextId === contextId) { refresh(); return }
        persistRecovery()
        if (contextId) contextCache[contextId] = { document: Review.copy(document), url: savedUrl, dirty: dirty }
        draft = null; textEditor.close(); relocatingId = ""; history = []; future = []
        contextId = nextId; recoveryUrl = view.reviewRecoveryPath(); savedUrl = ""; dirty = false; error = ""
        document = Review.empty(contextId)
        if (contextCache[contextId]) {
            var cached = contextCache[contextId]
            document = cached.document; savedUrl = cached.url; dirty = cached.dirty
        } else if (contextId && recoveryUrl) {
            var recovered = view.loadReview(recoveryUrl)
            if (recovered) {
                try { document = Review.decode(recovered, contextId); dirty = true }
                catch (e) { error = qsTr("Bozza recuperata non leggibile: ") + e.message }
            }
        }
        refresh()
    }
    function refresh() {
        resolved = document.marks.map(function(m) { return { mark: m, geometry: view.reviewAnchorGeometry(m.anchor) } })
        ink.requestPaint()
    }
    function change(next) {
        history = history.concat([Review.copy(document)]).slice(-40)
        future = []
        document = next; dirty = true
        persistRecovery(); refresh()
    }
    function undo() {
        if (!history.length) return
        future = future.concat([Review.copy(document)])
        document = history[history.length - 1]; history = history.slice(0, -1)
        dirty = true; persistRecovery(); refresh()
    }
    function redo() {
        if (!future.length) return
        history = history.concat([Review.copy(document)])
        document = future[future.length - 1]; future = future.slice(0, -1)
        dirty = true; persistRecovery(); refresh()
    }
    function finishMark(mark) {
        var next = Review.copy(document); next.marks.push(mark); change(next)
    }
    function removeMark(id) {
        var next = Review.copy(document)
        next.marks = next.marks.filter(function(m) { return m.id !== id }); change(next)
    }
    function setDisposition(id, status) {
        var next = Review.copy(document)
        next.marks.forEach(function(m) { if (m.id === id) m.status = status }); change(next)
    }
    function anchorError(reason) {
        if (reason === "save-score") return qsTr("Salva prima lo spartito, poi aggiungi la revisione.")
        if (reason === "outside-page") return qsTr("Scegli un punto all'interno della pagina.")
        return qsTr("Nessuna battuta visibile in questa pagina. Espandi le pause multimisura se necessario.")
    }
    function importFile(url) {
        try {
            var next = Review.decode(view.loadReview(url), contextId)
            change(next); savedUrl = url.toString(); dirty = false; error = ""
        } catch (e) { error = e.message }
    }
    Component.onCompleted: switchContext()
    Timer {
        interval: 1000
        repeat: true
        running: !root.contextId && root.visible
        onTriggered: root.switchContext()
    }
    Connections {
        target: root.view
        function onReviewContextChanged() { root.switchContext() }
        function onReviewLayoutChanged() { root.refresh() }
        function onMatrixChanged() { ink.requestPaint() }
        function onReviewActiveChanged() {
            root.draft = null; root.relocatingId = ""; textEditor.close(); root.refresh()
        }
    }

    Canvas {
        id: ink
        anchors.fill: parent
        visible: root.showMarks
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onPaint: {
            var ctx = getContext("2d")
            ctx.reset()
            var entries = root.resolved.slice()
            if (root.draft) entries.push({mark: root.draft, geometry: root.draftGeometry})
            entries.forEach(function(entry) {
                var m = entry.mark, g = entry.geometry
                if (!g.valid) return
                var points = Review.projected(m, g).map(function(p) { return root.view.reviewToView(Qt.point(p.x, p.y)) })
                if (!points.length) return
                var a = root.view.reviewToView(Qt.point(g.x, g.y))
                var b = root.view.reviewToView(Qt.point(g.x + g.spatium, g.y))
                var scale = Math.abs(b.x - a.x)
                ctx.strokeStyle = m.status === "draft" ? "#c23c36" : (m.status === "archive" ? "#7c5295" : "#244e80")
                ctx.fillStyle = ctx.strokeStyle
                ctx.lineWidth = Math.max(0.6, 0.22 * scale); ctx.lineCap = "round"; ctx.lineJoin = "round"
                if (m.type === "text") {
                    ctx.font = Math.max(1, 1.8 * scale) + "px sans-serif"
                    m.text.split("\n").forEach(function(line, i) { ctx.fillText(line, points[0].x, points[0].y + i * 2.2 * scale) })
                } else if (points.length === 1) {
                    ctx.beginPath(); ctx.arc(points[0].x, points[0].y, ctx.lineWidth / 2, 0, 2 * Math.PI); ctx.fill()
                } else {
                    ctx.beginPath(); ctx.moveTo(points[0].x, points[0].y)
                    for (var i = 1; i < points.length; ++i) ctx.lineTo(points[i].x, points[i].y)
                    ctx.stroke()
                }
            })
        }
    }
    MouseArea {
        id: drawing
        anchors.fill: parent
        enabled: root.active
        acceptedButtons: Qt.LeftButton
        cursorShape: root.tool === "text" ? Qt.IBeamCursor : Qt.CrossCursor
        onPressed: function(mouse) {
            var geometry = root.view.reviewAnchorAt(Qt.point(mouse.x, mouse.y))
            if (!geometry.valid) { root.error = root.anchorError(geometry.reason); return }
            root.error = ""
            var p = root.view.reviewToScore(Qt.point(mouse.x, mouse.y))
            if (root.relocatingId) {
                var next = Review.copy(root.document)
                next.marks = next.marks.map(function(m) { return m.id === root.relocatingId ? Review.relocate(m, geometry, p) : m })
                root.change(next); root.relocatingId = ""; return
            }
            if (root.tool === "text") {
                root.textGeometry = geometry; root.textScorePoint = p
                textInput.text = ""; textEditor.open(); textInput.forceActiveFocus(); return
            }
            root.draftGeometry = geometry
            root.draft = Review.makeMark("stroke", geometry, p)
            ink.requestPaint()
        }
        onPositionChanged: function(mouse) {
            if (!pressed || !root.draft) return
            if (root.draft.points.length >= 100000) return
            var p = root.view.reviewToScore(Qt.point(mouse.x, mouse.y))
            root.draft.points.push(Review.offset(root.draftGeometry, p)); ink.requestPaint()
        }
        onReleased: {
            if (root.draft) { root.finishMark(root.draft); root.draft = null; ink.requestPaint() }
        }
        onCanceled: { root.draft = null; ink.requestPaint() }
        // Wheel events propagate to the score's scrolling/zooming area.
        onWheel: function(wheel) { wheel.accepted = false }
    }

    Pane {
        id: tools
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        padding: 6
        background: Rectangle { color: "#f4f5f7"; border.color: "#bdc4cf" }
        ColumnLayout {
            anchors.fill: parent
            Flow {
                Layout.fillWidth: true
                spacing: 4
                Button {
                    text: root.active ? qsTr("Termina revisione") : qsTr("Revisione")
                    enabled: !!root.contextId
                    onClicked: { root.view.reviewActive = !root.active; root.showMarks = true }
                }
                Button { text: qsTr("Penna"); visible: root.active; checkable: true; checked: root.tool === "pen"; onClicked: root.tool = "pen" }
                Button { text: qsTr("Testo"); visible: root.active; checkable: true; checked: root.tool === "text"; onClicked: root.tool = "text" }
                Button { text: qsTr("Annulla"); visible: root.active; enabled: root.history.length > 0; onClicked: root.undo() }
                Button { text: qsTr("Ripeti"); visible: root.active; enabled: root.future.length > 0; onClicked: root.redo() }
                Button { text: qsTr("Accetta · stampa"); visible: root.active; onClicked: root.change(Review.acceptDrafts(root.document, "print")) }
                Button { text: qsTr("Accetta · archivio"); visible: root.active; onClicked: root.change(Review.acceptDrafts(root.document, "archive")) }
                Button { text: qsTr("Scarta nuove"); visible: root.active; onClicked: root.change(Review.discardDrafts(root.document)) }
                Button { text: root.dirty ? qsTr("Salva revisione *") : qsTr("Salva revisione"); enabled: !!root.contextId; onClicked: saveDialog.open() }
                Button { text: qsTr("Apri revisione"); enabled: !!root.contextId; onClicked: openDialog.open() }
                Button { text: qsTr("PDF con segni"); enabled: !!root.contextId; onClicked: pdfDialog.open() }
                CheckBox { text: qsTr("Mostra segni"); checked: root.showMarks; onToggled: root.showMarks = checked }
                CheckBox { id: listToggle; text: qsTr("Annotazioni") + " (" + root.document.marks.length + ")"; checked: false }
            }
            Label {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                visible: text.length > 0
                color: "#92392e"
                text: root.error || (!root.contextId ? qsTr("Salva lo spartito per attivare la revisione.") :
                    (root.relocatingId ? qsTr("Clicca sullo spartito per ricollocare il segno.") :
                    (root.orphanCount ? qsTr("Da ricollocare o nascosti: ") + root.orphanCount : "")))
            }
        }
    }
    Pane {
        anchors.top: tools.bottom
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        width: Math.min(300, parent.width * 0.4)
        visible: listToggle.checked
        background: Rectangle { color: "#f4f5f7"; border.color: "#bdc4cf" }
        ScrollView {
            anchors.fill: parent
            contentWidth: availableWidth
            Column {
                width: parent.width
                spacing: 8
                Repeater {
                    model: root.resolved
                    delegate: Frame {
                        id: reviewEntry
                        required property var modelData
                        required property int index
                        width: parent.width
                        ColumnLayout {
                            width: parent.width
                            Label {
                                Layout.fillWidth: true
                                wrapMode: Text.Wrap
                                text: (reviewEntry.modelData.geometry.valid ? "" : reviewEntry.modelData.geometry.reason === "hidden" ? qsTr("Nascosto · ") : qsTr("Da ricollocare · "))
                                    + (reviewEntry.modelData.mark.type === "text" ? reviewEntry.modelData.mark.text : qsTr("Tratto ") + (reviewEntry.index + 1))
                            }
                            ComboBox {
                                Layout.fillWidth: true
                                model: [qsTr("In revisione"), qsTr("Accettato · stampa"), qsTr("Accettato · archivio")]
                                currentIndex: ["draft", "print", "archive"].indexOf(reviewEntry.modelData.mark.status)
                                onActivated: root.setDisposition(reviewEntry.modelData.mark.id, ["draft", "print", "archive"][currentIndex])
                            }
                            RowLayout {
                                Button { text: qsTr("Ricolloca"); onClicked: { root.view.reviewActive = true; root.relocatingId = reviewEntry.modelData.mark.id } }
                                Button { text: qsTr("Elimina"); onClicked: root.removeMark(reviewEntry.modelData.mark.id) }
                            }
                        }
                    }
                }
            }
        }
    }
    Dialog {
        id: textEditor
        objectName: "reviewTextEditor"
        title: qsTr("Testo sulla partitura")
        anchors.centerIn: parent
        modal: true
        width: Math.min(440, root.width - 20)
        standardButtons: Dialog.Ok | Dialog.Cancel
        TextArea { id: textInput; objectName: "reviewTextInput"; width: parent.width; implicitHeight: 140; wrapMode: TextEdit.Wrap }
        onAccepted: {
            if (textInput.text.trim()) root.finishMark(Review.makeMark("text", root.textGeometry, root.textScorePoint, textInput.text))
        }
    }
    FileDialog {
        id: saveDialog
        title: qsTr("Salva revisione separata")
        fileMode: FileDialog.SaveFile
        defaultSuffix: "json"
        nameFilters: [qsTr("Revisione (*.json)")]
        onAccepted: {
            if (root.view.saveReview(selectedFile, JSON.stringify(root.document))) {
                root.savedUrl = selectedFile.toString(); root.dirty = false; root.error = ""
            } else root.error = qsTr("Impossibile salvare la revisione.")
        }
    }
    FileDialog {
        id: openDialog
        title: qsTr("Apri revisione separata")
        fileMode: FileDialog.OpenFile
        nameFilters: [qsTr("Revisione (*.json)")]
        onAccepted: {
            if (root.dirty && root.document.marks.length) replaceDialog.open()
            else root.importFile(selectedFile)
        }
    }
    Dialog {
        id: replaceDialog
        anchors.centerIn: parent
        modal: true
        title: qsTr("Sostituire la revisione aperta?")
        standardButtons: Dialog.Ok | Dialog.Cancel
        Label { text: qsTr("Le modifiche non esportate saranno sostituite. Puoi annullare l'importazione con Annulla."); wrapMode: Text.Wrap; width: 300 }
        onAccepted: root.importFile(openDialog.selectedFile)
    }
    FileDialog {
        id: pdfDialog
        title: qsTr("Esporta spartito con revisioni stampabili")
        fileMode: FileDialog.SaveFile
        defaultSuffix: "pdf"
        nameFilters: [qsTr("PDF (*.pdf)")]
        onAccepted: {
            if (!root.view.exportReviewPdf(selectedFile, JSON.stringify(root.document))) root.error = qsTr("Esportazione PDF non riuscita.")
            else root.error = ""
        }
    }
}
