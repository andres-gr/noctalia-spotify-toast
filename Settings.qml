import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Widgets

ColumnLayout {
  id: root

  property var pluginApi: null

  property var cfg: pluginApi?.pluginSettings || ({})
  property var defaults: pluginApi?.manifest?.metadata?.defaultSettings || ({})

  // Use string for currentKey since NComboBox expects string keys
  property string toastDuration: String(cfg.toastDuration ?? defaults.toastDuration ?? "4000")

  spacing: Style.marginL

  Component.onCompleted: {
    Logger.i("SpotifyArtToast", "Settings UI loaded");
  }

  NComboBox {
    Layout.fillWidth: true
    label: "Toast Duration"
    description: "How long the toast notification stays visible"
    model: [
      { "key": "1000", "name": "1 second" },
      { "key": "2000", "name": "2 seconds" },
      { "key": "3000", "name": "3 seconds" },
      { "key": "4000", "name": "4 seconds" },
      { "key": "5000", "name": "5 seconds" },
      { "key": "6000", "name": "6 seconds" },
      { "key": "8000", "name": "8 seconds" }
    ]
    currentKey: root.toastDuration
    onSelected: function (key) {
      root.toastDuration = key;
    }
    defaultValue: "2000"
  }

  function saveSettings() {
    if (!pluginApi) {
      Logger.e("SpotifyArtToast", "Cannot save settings: pluginApi is null");
      return;
    }

    // Convert string key back to integer for storage
    pluginApi.pluginSettings.toastDuration = parseInt(root.toastDuration, 10);
    pluginApi.saveSettings();

    Logger.i("SpotifyArtToast", "Settings saved successfully");
    pluginApi.closePanel(root.screen);
  }
}
