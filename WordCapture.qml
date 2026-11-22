import QtQuick
import qs.Commons
import qs.Ui

// The bar button. The panel (Panel.qml) is created on the first click and
// kept from then on, so until it is used the bar holds only this button: no
// panel window, file reads, watches or processes.
//
// Bar.findPanelWidget routes shell summon/hide/toggle to open/close/opened
// on this root, so they are forwarded here, as the built-in clock does.
BarWidget {
  id: root
  moduleName: "lipionix.word-capture"
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  // Read back by KeyboardPanel off its owner during a popout switch.
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  // The panel, created on first use (synchronously, so it is ready to open).
  function panel() {
    if (!panelLoader.item) {
      panelLoader.active = true
      injectPanel()
    }
    return panelLoader.item
  }

  function open() { var target = panel(); if (target) target.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function toggle() { var target = panel(); if (target) target.toggle() }
  function togglePanel() { toggle() }
  function closeForPopoutSwitch() { if (panelLoader.item) panelLoader.item.closeForPopoutSwitch() }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    target.bar = root.bar
    target.settings = root.settings
    target.anchorItem = button
    target.hostWidget = root
  }

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  Loader {
    id: panelLoader
    active: false
    visible: false
    source: Qt.resolvedUrl("Panel.qml")
    onLoaded: root.injectPanel()
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    // Nerd Font md-book_plus in the bar's own font and slot, like the built-in
    // widgets: "add to the book".
    text: "󰗛"
    tooltipText: "Word capture"
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) { var target = root.panel(); if (target) target.openFile() }
      else if (buttonCode !== Qt.MiddleButton) root.toggle()
    }
  }
}
