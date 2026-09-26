/*
 * SPDX-License-Identifier: GPL-3.0-only
 * MuseScore-Studio-CLA-applies
 *
 * MuseScore Studio
 * Music Composition & Notation
 *
 * Copyright (C) 2021 MuseScore Limited and others
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License version 3 as
 * published by the Free Software Foundation.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls

import Muse.Ui
import Muse.UiComponents
import MuseScore.NotationScene
import MuseScore.Braille
import MuseScore.Playback

import "internal"

FocusScope {
    id: root

    property alias name: notationView.objectName
    property alias publishMode: notationView.publishMode
    property alias readOnly: notationView.readOnly

    property alias paintView: notationView
    property bool reviewMode: false
    property bool reviewAccepted: false
    property bool reviewPreviousReadOnly: false
    property var reviewMarks: []
    property var reviewDraft: null
    property string reviewTool: "pen"

    function setReviewMode(enabled) {
        if (enabled === reviewMode)
            return
        if (enabled) {
            reviewPreviousReadOnly = notationView.readOnly
            notationView.readOnly = true
        } else {
            notationView.readOnly = reviewPreviousReadOnly
        }
        reviewMode = enabled
        reviewCanvas.requestPaint()
    }

    function reviewPoint(x, y) {
        const p = notationView.reviewToScore(Qt.point(x, y))
        return { x: p.x, y: p.y }
    }

    function addReviewText(value, x, y) {
        if (!value.trim())
            return
        reviewMarks = reviewMarks.concat([{ type: "text", points: [reviewPoint(x, y)], text: value }])
        reviewCanvas.requestPaint()
    }

    property alias isNavigatorVisible: notationNavigator.visible
    property alias isBraillePanelVisible: brailleViewLoader.active
    property alias isMainView: notationView.isMainView

    property alias defaultNavigationControl: fakeNavCtrl

    readonly property alias navigationSection: navSec
    readonly property alias navigationOrderEnd: searchPopup.navigationOrderEnd

    NavigationSection {
        id: navSec
        name: "NotationView"
        order: 5
        enabled: root.visible
    }

    QtObject {
        id: prv
        readonly property int scrollbarMargin: 4
    }

    NotationContextMenuModel {
        id: contextMenuModel
    }

    Component.onCompleted: {
        notationView.load()
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        NotationSwitchPanel {
            id: tabPanel
            Layout.fillWidth: true

            navigationPanel.section: navSec
            navigationPanel.order: 1
        }

        SeparatorLine { visible: tabPanel.visible }

        RowLayout {
            Layout.fillWidth: true
            visible: !notationView.publishMode
            spacing: 6
            Button {
                text: root.reviewMode ? qsTr("Close review") : qsTr("Review")
                onClicked: root.setReviewMode(!root.reviewMode)
            }
            Button {
                text: qsTr("Pen")
                visible: root.reviewMode
                enabled: !root.reviewAccepted
                onClicked: root.reviewTool = "pen"
            }
            Button {
                text: qsTr("Text")
                visible: root.reviewMode
                enabled: !root.reviewAccepted
                onClicked: root.reviewTool = "text"
            }
            Button {
                text: qsTr("Accept review")
                visible: root.reviewMode
                enabled: !root.reviewAccepted
                onClicked: {
                    root.reviewAccepted = true
                    reviewCanvas.requestPaint()
                }
            }
            Button {
                text: qsTr("Discard review")
                visible: root.reviewMode
                onClicked: {
                    root.reviewMarks = []
                    root.reviewAccepted = false
                    reviewCanvas.requestPaint()
                }
            }
            Label {
                text: qsTr("Review marks are not saved yet")
                visible: root.reviewMode
            }
        }

        SplitView {
            id: splitView

            Layout.fillWidth: true
            Layout.fillHeight: true

            orientation: notationNavigator.orientation === Qt.Horizontal ? Qt.Vertical : Qt.Horizontal

            StyledViewScrollAndZoomArea {
                SplitView.fillWidth: true
                SplitView.fillHeight: true

                horizontalScrollbarSize: notationView.horizontalScrollbarSize
                startHorizontalScrollPosition: notationView.startHorizontalScrollPosition

                verticalScrollbarSize: notationView.verticalScrollbarSize
                startVerticalScrollPosition: notationView.startVerticalScrollPosition

                NotationPaintView {
                    id: notationView
                    anchors.fill: parent

                    onMatrixChanged: reviewCanvas.requestPaint()

                    Canvas {
                        id: reviewCanvas
                        anchors.fill: parent
                        visible: root.reviewMode
                        onPaint: {
                            const ctx = getContext("2d")
                            ctx.clearRect(0, 0, width, height)
                            const marks = root.reviewDraft ? root.reviewMarks.concat([root.reviewDraft]) : root.reviewMarks
                            ctx.strokeStyle = root.reviewAccepted ? "#255d91" : "#bf3030"
                            ctx.fillStyle = ctx.strokeStyle
                            ctx.lineWidth = 2
                            ctx.lineCap = "round"
                            ctx.lineJoin = "round"
                            for (const mark of marks) {
                                if (mark.type === "text") {
                                    const p = notationView.reviewToView(Qt.point(mark.points[0].x, mark.points[0].y))
                                    ctx.font = "18px sans-serif"
                                    ctx.fillText(mark.text, p.x, p.y)
                                    continue
                                }
                                ctx.beginPath()
                                for (let i = 0; i < mark.points.length; ++i) {
                                    const p = notationView.reviewToView(Qt.point(mark.points[i].x, mark.points[i].y))
                                    if (i === 0) ctx.moveTo(p.x, p.y)
                                    else ctx.lineTo(p.x, p.y)
                                }
                                ctx.stroke()
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            enabled: root.reviewMode && !root.reviewAccepted
                            onPressed: function(mouse) {
                                if (root.reviewTool === "text") {
                                    reviewText.x = Math.min(mouse.x, reviewCanvas.width - reviewText.width)
                                    reviewText.y = Math.min(mouse.y, reviewCanvas.height - reviewText.height)
                                    reviewText.scoreX = mouse.x
                                    reviewText.scoreY = mouse.y
                                    reviewText.visible = true
                                    reviewInput.forceActiveFocus()
                                    return
                                }
                                root.reviewDraft = { type: "stroke", points: [root.reviewPoint(mouse.x, mouse.y)] }
                                reviewCanvas.requestPaint()
                            }
                            onPositionChanged: function(mouse) {
                                if (!pressed || !root.reviewDraft) return
                                root.reviewDraft.points.push(root.reviewPoint(mouse.x, mouse.y))
                                reviewCanvas.requestPaint()
                            }
                            onReleased: {
                                if (!root.reviewDraft) return
                                root.reviewMarks = root.reviewMarks.concat([root.reviewDraft])
                                root.reviewDraft = null
                                reviewCanvas.requestPaint()
                            }
                        }
                    }

                    Rectangle {
                        id: reviewText
                        property real scoreX: 0
                        property real scoreY: 0
                        width: 270
                        height: 85
                        color: "white"
                        border.color: "#555555"
                        visible: false
                        z: 10
                        Column {
                            anchors.fill: parent
                            anchors.margins: 4
                            TextField {
                                id: reviewInput
                                width: parent.width
                                placeholderText: qsTr("Write on the score")
                                onAccepted: reviewSave.clicked()
                            }
                            Row {
                                Button {
                                    id: reviewSave
                                    text: qsTr("Insert")
                                    onClicked: {
                                        root.addReviewText(reviewInput.text, reviewText.scoreX, reviewText.scoreY)
                                        reviewInput.text = ""
                                        reviewText.visible = false
                                    }
                                }
                                Button {
                                    text: qsTr("Cancel")
                                    onClicked: reviewText.visible = false
                                }
                            }
                        }
                    }

                    property NavigationPanel navigationPanel: NavigationPanel {
                        name: "ScoreView"
                        section: navSec
                        enabled: notationView.enabled && notationView.visible
                        direction: NavigationPanel.Both
                        order: tabPanel.navigationPanel.order + 1
                    }

                    NavigationControl {
                        id: fakeNavCtrl
                        name: "Score"
                        enabled: notationView.enabled && notationView.visible

                        panel: notationView.navigationPanel
                        order: 1

                        onActiveChanged: {
                            if (fakeNavCtrl.active) {
                                notationView.forceFocusIn()

                                if (notationView.navigationPanel.highlight) {
                                    notationView.selectOnNavigationActive()
                                }
                            } else {
                                notationView.focus = false
                            }
                        }
                    }

                    NavigationFocusBorder {
                        navigationCtrl: fakeNavCtrl
                        drawOutsideParent: false
                    }

                    Rectangle {
                        id: playbackCursor

                        Component.onCompleted: {
                            notationView.setPlaybackCursorItem(playbackCursor)
                        }
                    }

                    onActiveFocusRequested: {
                        fakeNavCtrl.requestActive()
                    }

                    onShowContextMenuRequested: function (elementType, viewPos) {
                        contextMenuModel.loadItems(elementType)
                        contextMenuLoader.show(viewPos, contextMenuModel.items)
                    }

                    onHideContextMenuRequested: {
                        contextMenuLoader.close()
                    }

                    onShowSearchRequested: {
                        searchPopup.show()        
                    }

                    onShowElementPopupRequested: function (popupType) {
                        popUpLoader.updateShow(popupType);
                    }

                    onHideElementPopupRequested: {
                        popUpLoader.updateShow(AbstractElementPopupModel.TYPE_UNDEFINED);
                    }

                    onViewportChanged: {
                        notationNavigator.setCursorRect(viewport)
                    }

                    ContextMenuLoader {
                        id: contextMenuLoader

                        onHandleMenuItem: function(itemId) {
                            contextMenuModel.handleMenuItem(itemId)
                        }

                        onOpened: notationView.onContextMenuIsOpenChanged(true)
                        onClosed: notationView.onContextMenuIsOpenChanged(false)
                    }

                    ElementPopupLoader {
                        id: popUpLoader

                        notationViewNavigationSection: navSec
                        navigationOrderStart: notationView.navigationPanel.order + 1

                        property int popupType: AbstractElementPopupModel.TYPE_UNDEFINED
                        property bool updateShowScheduled: false

                        function updateShow(popupType) {
                            this.popupType = popupType;
                            if (!updateShowScheduled) {
                                Qt.callLater(doUpdateShow)
                                updateShowScheduled = true;
                            }
                        }

                        function doUpdateShow() {
                            updateShowScheduled = false;

                            if (popupType !== AbstractElementPopupModel.TYPE_UNDEFINED) {
                                show(popupType);
                            } else {
                                close();
                            }
                        }

                        onOpened: function(popupType) {
                            notationView.onElementPopupIsOpenChanged(popupType)
                        }

                        onClosed: {
                            notationView.onElementPopupIsOpenChanged(AbstractElementPopupModel.TYPE_UNDEFINED)
                        }
                    }

                    NotationRegionsBeingProcessedView {
                        notationViewRect: Qt.rect(notationView.x, notationView.y, notationView.width, notationView.height)
                        notationViewMatrix: notationView.matrix
                    }
                }

                onPinchToZoom: function(scale, pos) {
                    notationView.pinchToZoom(scale, pos)
                }

                onScrollHorizontal: function(newPos) {
                    notationView.scrollHorizontal(newPos)
                }

                onScrollVertical: function(newPos) {
                    notationView.scrollVertical(newPos)
                }
            }

            Loader {
                id: notationNavigator

                readonly property NotationNavigator navigatorItem: item as NotationNavigator

                property var orientation: navigatorItem?.orientation ?? Qt.Horizontal

                visible: false

                SplitView.preferredHeight: 100
                SplitView.preferredWidth: 100
                SplitView.minimumWidth: 30
                SplitView.minimumHeight: 30

                sourceComponent: visible ? navigatorComp : null

                function setCursorRect(viewport) {
                    if (navigatorItem) {
                        navigatorItem.setCursorRect(viewport)
                    }
                }
            }

            Loader {
                id: brailleViewLoader

                readonly property int navigationOrder: popUpLoader.navigationOrderEnd + 1

                active: false
                visible: active

                SplitView.fillWidth: true
                SplitView.preferredHeight: 50
                SplitView.minimumHeight: 30

                sourceComponent: BrailleView {
                    navigationPanel.section: navSec
                    navigationPanel.order: brailleViewLoader.navigationOrder

                    navigationPanel.onActiveChanged: function (active) {
                        if (active) {
                            notationView.navigationPanel.setActive(false);
                            fakeNavCtrl.setActive(false);
                        }
                    }
                }
            }

            Component {
                id: navigatorComp

                NotationNavigator {

                    property bool isVertical: orientation === Qt.Vertical

                    objectName: root.name + "Navigator"

                    Component.onCompleted: {
                        load()
                    }

                    onMoveNotationRequested: function(dx, dy) {
                        notationView.moveCanvas(dx, dy)
                    }
                }
            }

            handle: Rectangle {
                id: resizingHandle

                implicitWidth: 4
                implicitHeight: 4

                color: ui.theme.strokeColor

                states: [
                    State {
                        name: "PRESSED"
                        when: resizingHandle.SplitHandle.pressed
                        PropertyChanges {
                            target: resizingHandle
                            opacity: ui.theme.accentOpacityHit
                        }
                    },
                    State {
                        name: "HOVERED"
                        when: resizingHandle.SplitHandle.hovered
                        PropertyChanges {
                            target: resizingHandle
                            opacity: ui.theme.accentOpacityHover
                        }
                    }
                ]
            }
        }

        SearchPopup {
            id: searchPopup

            Layout.fillWidth: true

            navigationPanel.section: navSec
            navigationOrderStart: brailleViewLoader.navigationOrder + 1

            onClosed: {
                fakeNavCtrl.requestActive()
            }
        }
    }
}
