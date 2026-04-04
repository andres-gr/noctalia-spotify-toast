import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Services.Media
import qs.Services.UI
import qs.Widgets

Item {
    id: root
    property var pluginApi: null
    property string lastTitle: ""
    readonly property var ignoredTitles: ["Advertisement"]

    // Plugin settings - configurable via plugin settings
    readonly property int toastDuration: (root.pluginApi && root.pluginApi.pluginSettings && root.pluginApi.pluginSettings.toastDuration) || 4000

    // ── MediaService watchers ─────────────────────────────────────────────
    Connections {
        target: MediaService

        function onTrackTitleChanged() {
            var title = MediaService.trackTitle;
            if (!title || root.ignoredTitles.includes(title)) return;
            if (!MediaService.playerIdentity.toLowerCase().includes("spotify")) return;
            if (title === root.lastTitle) return;
            root.lastTitle = title;
            console.log("[SpotifyToast] SONG CHANGE: " + title);

            // Use Qt.callLater to defer reading values by one event loop iteration,
            // allowing QML's reactive bindings to propagate the new trackArtUrl
            Qt.callLater(function() {
                root.queueNotification(
                    MediaService.trackTitle,
                    MediaService.trackArtist,
                    MediaService.trackArtUrl
                );
            });
        }

        function onIsPlayingChanged() {
            if (!MediaService.isPlaying) return;
            if (!MediaService.playerIdentity.toLowerCase().includes("spotify")) return;
            var title = MediaService.trackTitle;
            if (!title || root.ignoredTitles.includes(title)) return;
            console.log("[SpotifyToast] RESUME CHECK: title=" + title + " lastTitle=" + root.lastTitle + " equal=" + (title === root.lastTitle));
            // Allow showing toast even if title hasn't changed - user may have paused/stopped and resumed
            root.lastTitle = title;
            console.log("[SpotifyToast] RESUMED: " + title);
            root.queueNotification(title, MediaService.trackArtist, MediaService.trackArtUrl);
        }
    }

    // ── Debounce ──────────────────────────────────────────────────────────
    Timer {
        id: notifyDebounce
        interval: 150  // Short debounce to coalesce extremely rapid changes
        repeat: false
        property string pendingTitle: ""
        property string pendingArtist: ""
        property string pendingArtUrl: ""
        onTriggered: spotifyToastLoader.showToast(pendingTitle, pendingArtist, pendingArtUrl)
    }

    function queueNotification(title, artist, artUrl) {
        // Always stop any pending debounce and queue fresh data
        notifyDebounce.stop();
        notifyDebounce.pendingTitle  = title;
        notifyDebounce.pendingArtist = Array.isArray(artist) ? artist.join(", ") : (artist || "");
        notifyDebounce.pendingArtUrl = artUrl || "";

        // If toast is currently showing, dismiss it immediately and show new one
        if (spotifyToastLoader.active && spotifyToastLoader.item) {
            spotifyToastLoader.item.hideImmediately();
            spotifyToastLoader.active = false;
        }

        // Restart with short delay - just enough to coalesce very rapid changes
        notifyDebounce.interval = 150;
        notifyDebounce.start();
    }

    // ── PanelWindow loader — same pattern as ToastScreen.qml ─────────────
    // Destroyed when not visible to free memory, recreated on next toast
    Loader {
        id: spotifyToastLoader
        active: false
        property var pendingData: null

        function showToast(title, artist, artUrl) {
            // If already showing, update the content directly instead of recreating
            if (active && item && item.updateToast) {
                item.updateToast(title, artist, artUrl);
                pendingData = null;
                return;
            }

            pendingData = { title: title, artist: artist, artUrl: artUrl };
            active = true;
        }

        onStatusChanged: {
            if (status === Loader.Ready && pendingData !== null) {
                item.show(pendingData.title, pendingData.artist, pendingData.artUrl);
                pendingData = null;
            }
        }

        sourceComponent: PanelWindow {
            id: panel

            // ── Mirror ToastScreen.qml positioning logic exactly ──────────
            readonly property string location: Settings.data.notifications?.location || "top_right"
            readonly property bool isTop:      location.startsWith("top")
            readonly property bool isBottom:   location.startsWith("bottom")
            readonly property bool isLeft:     location.endsWith("_left")
            readonly property bool isRight:    location.endsWith("_right")

            readonly property string barPos:       Settings.getBarPositionForScreen(panel.screen?.name)
            readonly property bool   isFloating:   Settings.data.bar.barType === "floating"
            readonly property bool   isFramed:     Settings.data.bar.barType === "framed"
            readonly property real   frameThickness: Settings.data.bar.frameThickness ?? 8
            readonly property real   barHeight:    Style.getBarHeightForScreen(panel.screen?.name)

            readonly property int barOffsetTop: {
                if (barPos !== "top") return isFramed ? frameThickness : 0;
                return barHeight + (isFloating ? Math.ceil(Settings.data.bar.marginVertical) : 0);
            }
            readonly property int barOffsetBottom: {
                if (barPos !== "bottom") return isFramed ? frameThickness : 0;
                return barHeight + (isFloating ? Math.ceil(Settings.data.bar.marginVertical) : 0);
            }
            readonly property int barOffsetLeft: {
                if (barPos !== "left") return isFramed ? frameThickness : 0;
                return barHeight + (isFloating ? Math.ceil(Settings.data.bar.marginHorizontal) : 0);
            }
            readonly property int barOffsetRight: {
                if (barPos !== "right") return isFramed ? frameThickness : 0;
                return barHeight + (isFloating ? Math.ceil(Settings.data.bar.marginHorizontal) : 0);
            }

            readonly property int shadowPadding: Style.shadowBlurMax + Style.marginL

            anchors.top:    isTop
            anchors.bottom: isBottom
            anchors.left:   isLeft
            anchors.right:  isRight

            margins.top:    isTop    ? barOffsetTop    - shadowPadding + Style.marginM : 0
            margins.bottom: isBottom ? barOffsetBottom - shadowPadding + Style.marginM : 0
            margins.left:   isLeft   ? barOffsetLeft   - shadowPadding + Style.marginM : 0
            margins.right:  isRight  ? barOffsetRight  - shadowPadding + Style.marginM : 0

            implicitWidth:  toastItem.width
            implicitHeight: toastItem.height

            color: "transparent"

            WlrLayershell.layer:         WlrLayer.Top
            WlrLayershell.namespace:     "noctalia-spotify-toast"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            WlrLayershell.exclusionMode: ExclusionMode.Ignore

            // Shadow area is click-through, content area is clickable
            mask: Region {
                x: 0; y: 0
                width: panel.width; height: panel.height
                intersection: Intersection.Xor
                Region {
                    x: panel.shadowPadding
                    y: panel.shadowPadding
                    width:  Math.max(0, panel.width  - panel.shadowPadding * 2)
                    height: Math.max(0, panel.height - panel.shadowPadding * 2)
                    intersection: Intersection.Subtract
                }
            }

            function show(title, artist, artUrl) {
                toastItem.show(title, artist, artUrl);
            }

            function updateToast(title, artist, artUrl) {
                toastItem.updateContent(title, artist, artUrl);
            }

            function hideImmediately() {
                toastItem.hideImmediately();
            }

            // ── Toast visual — Toast.qml layout with Image instead of NIcon ──
            Item {
                id: toastItem

                readonly property int notificationWidth: Math.round(
                    (Settings.data.notifications?.density === "compact" ? 320 : 440)
                    * Style.uiScaleRatio)

                width:  notificationWidth + panel.shadowPadding * 2
                height: Math.round(contentRow.implicitHeight + Style.margin2M * 2 + panel.shadowPadding * 2)

                property real progress: 1.0
                readonly property real initialScale: 0.7

                function show(title, artist, artUrl) {
                    artImage.imagePath = artUrl || "";
                    trackTitle.text  = title;
                    trackArtist.text = artist;
                    // reset
                    progressAnimation.stop();
                    toastBg.opacity = 0;
                    toastBg.scale   = initialScale;
                    progress        = 1.0;
                    // animate in
                    showAnim.start();
                    progressAnimation.restart();
                }

                // Update content without full reset - for rapid track changes
                function updateContent(title, artist, artUrl) {
                    artImage.imagePath = artUrl || "";
                    trackTitle.text  = title;
                    trackArtist.text = artist;
                    // Just reset progress to full, don't restart show animation
                    progressAnimation.stop();
                    progress = 1.0;
                    progressAnimation.restart();
                }

                function hide() {
                    progressAnimation.stop();
                    hideAnim.start();
                }

                function hideImmediately() {
                    progressAnimation.stop();
                    hideAnim.stop();
                    toastBg.opacity = 0;
                    toastBg.scale = toastItem.initialScale;
                    progress = 0;
                    // Notify parent to deactivate loader
                    hideAnimationImmediate.restart();
                }

                Timer {
                    id: hideAnimationImmediate
                    interval: 1
                    onTriggered: spotifyToastLoader.active = false
                }

                ParallelAnimation {
                    id: showAnim
                    NumberAnimation { target: toastBg; property: "opacity"; to: 1.0; duration: Style.animationNormal; easing.type: Easing.OutCubic }
                    NumberAnimation { target: toastBg; property: "scale";   to: 1.0; duration: Style.animationNormal; easing.type: Easing.OutCubic }
                }
                ParallelAnimation {
                    id: hideAnim
                    NumberAnimation { target: toastBg; property: "opacity"; to: 0.0; duration: Style.animationNormal; easing.type: Easing.InCubic }
                    NumberAnimation { target: toastBg; property: "scale";   to: toastItem.initialScale; duration: Style.animationNormal; easing.type: Easing.InCubic }
                    onFinished: spotifyToastLoader.active = false  // destroys PanelWindow
                }

                // Progress bar drives auto-dismiss
                NumberAnimation {
                    id: progressAnimation
                    target: toastItem
                    property: "progress"
                    from: 1.0; to: 0.0
                    duration: root.toastDuration
                    easing.type: Easing.Linear
                    onFinished: toastItem.hide()
                }

                Rectangle {
                    id: toastBg
                    anchors.fill: parent
                    anchors.margins: panel.shadowPadding
                    radius: Style.radiusL
                    opacity: 0
                    scale: toastItem.initialScale
                    color: Qt.alpha(Color.mSurface, Color.adaptiveOpacity(Settings.data.notifications.backgroundOpacity) || 1.0)
                    border.width: Style.borderS
                    border.color: Qt.alpha(Color.mOutline, Color.adaptiveOpacity(Settings.data.notifications.backgroundOpacity) || 1.0)

                    // Progress bar — matches Toast.qml exactly
                    Rectangle {
                        anchors.top: parent.top
                        anchors.left: parent.left
                        anchors.right: parent.right
                        height: 2
                        color: "transparent"
                        Rectangle {
                            readonly property real progressWidth: toastBg.width - 2 * toastBg.radius
                            height: parent.height
                            x: toastBg.radius + progressWidth * (1 - toastItem.progress) / 2
                            width: progressWidth * toastItem.progress
                            color: Qt.alpha(Color.mPrimary, Color.adaptiveOpacity(Settings.data.notifications.backgroundOpacity) || 1.0)
                        }
                    }

                    // Click to dismiss
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: toastItem.hide()
                    }

                    RowLayout {
                        id: contentRow
                        anchors {
                            left: parent.left; right: parent.right; top: parent.top
                            topMargin:   Style.margin2M
                            bottomMargin: Style.margin2M
                            leftMargin:  Style.margin2M
                            rightMargin: Style.margin2M
                        }
                        spacing: Style.marginL

                        // Album art using NImageRounded - same as other media widgets
                        NImageRounded {
                            id: artImage
                            readonly property int artSize: Math.round(52 * Style.uiScaleRatio)
                            width: artSize
                            height: artSize
                            radius: Style.radiusS
                            imagePath: ""
                            imageFillMode: Image.PreserveAspectCrop
                            fallbackIcon: "disc"
                            fallbackIconSize: Math.round(24 * Style.uiScaleRatio)
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignVCenter
                            spacing: Style.marginXXS

                            NText {
                                text: "Now Playing"
                                color: Color.mPrimary
                                pointSize: Style.fontSizeS
                                font.weight: Style.fontWeightBold
                            }

                            NText {
                                id: trackTitle
                                Layout.fillWidth: true
                                color: Color.mOnSurface
                                pointSize: Style.fontSizeL
                                font.weight: Style.fontWeightBold
                                wrapMode: Text.NoWrap
                                elide: Text.ElideRight
                            }

                            NText {
                                id: trackArtist
                                Layout.fillWidth: true
                                color: Color.mOnSurface
                                pointSize: Style.fontSizeS
                                wrapMode: Text.NoWrap
                                elide: Text.ElideRight
                                opacity: 0.7
                            }
                        }
                    }
                }

                NDropShadow {
                    anchors.fill: toastBg
                    source: toastBg
                    autoPaddingEnabled: true
                }
            }
        }
    }

    Component.onCompleted: console.log("[SpotifyToast] Loaded — PanelWindow with art.");
}
