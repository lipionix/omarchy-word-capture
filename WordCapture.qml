import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "alexander.word-capture"
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  property string statePath: Quickshell.env("HOME") + "/.local/state/omarchy/word-capture.json"
  property string word: ""
  property string context: ""
  property string language: "English"
  property string filePath: Quickshell.env("HOME") + "/Documents/words.md"
  property var languages: Model.defaults()
  property var matches: []
  property bool settingsOpen: false
  property bool writing: false
  property string pendingEntry: ""
  readonly property color foreground: bar ? bar.foreground : Commons.Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.55)

  // Reset view state on every open. onOpenedChanged alone proved unreliable
  // across shell restarts, so own the entry points the shell calls.
  function open() {
    settingsOpen = false
    controller.show()
  }
  function close() {
    settingsOpen = false
    controller.hide()
  }
  function toggle() { opened ? close() : open() }

  function loadState(raw) {
    try {
      var state = JSON.parse(String(raw || "{}"))
      if (state.filePath) filePath = Model.safeText(state.filePath, 500)
      if (state.languages) languages = Model.normalizeLanguages(state.languages)
      if (state.language) language = Model.safeText(state.language, 40)
    } catch (e) {}
  }

  function saveState() {
    stateFile.setText(JSON.stringify({ filePath: filePath, languages: languages, language: language }) + "\n")
  }

  function updateDetection() {
    // Detect from the word field only: mixing in context would cancel a
    // script match whenever the two fields use different alphabets.
    matches = Model.detect(word, languages)
    // Follow the first match. Keep the current language when it already
    // matches, so manually picking one of several lookalikes sticks.
    if (matches.length && matches.indexOf(language) === -1) language = matches[0]
  }

  function submit() {
    if (!word.trim() || !language.trim() || writing || !filePath.trim()) return
    pendingEntry = Model.markdownEntry(word, context, language)
    writing = true
    appendProcess.running = true
  }

  function finish(ok) {
    writing = false
    if (!ok) return
    word = ""
    context = ""
    pendingEntry = ""
    close()
  }

  function updateLanguage(index, name, characters) {
    var next = languages.slice()
    next[index] = { name: Model.safeText(name, 40).trim() || "Language", characters: characters }
    languages = Model.normalizeLanguages(next)
    saveState()
    updateDetection()
  }

  function removeLanguage(index) {
    if (languages.length < 2) return
    var next = languages.slice()
    next.splice(index, 1)
    languages = Model.normalizeLanguages(next)
    if (!languages.some(function(item) { return item.name === language })) language = languages[0].name
    saveState()
    updateDetection()
  }

  FileView {
    id: stateFile
    path: root.statePath
    atomicWrites: true
    printErrors: false
    onLoaded: root.loadState(text())
  }

  Process {
    id: appendProcess
    command: ["python3", "-c", "from pathlib import Path; import sys; p=Path(sys.argv[1]).expanduser(); p.parent.mkdir(parents=True, exist_ok=True); f=p.open('a', encoding='utf-8'); f.write(sys.argv[2]); f.close()", root.filePath, root.pendingEntry]
    onExited: function(exitCode) { root.finish(exitCode === 0) }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    slotSize: Style.bar.statusSlot
    text: "󰂺"
    fontFamily: "Symbols Nerd Font"
    tooltipText: "Word capture"
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton || buttonCode === Qt.MiddleButton) return
      root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    // The content stays loaded between opens, so focus the word field on
    // every open rather than once at creation.
    focusTarget: panel.loadedContent ? panel.loadedContent.wordField : null
    contentWidth: panel.fittedContentWidth(Style.space(420))
    // Follow the content, never a fixed height: fixed heights leave dead space.
    contentHeight: panel.fittedContentHeight(panel.loadedContentHeight, Style.space(620))

    content: PanelKeyCatcher {
      id: keyCatcher
      property alias wordField: wordField
      anchors.fill: parent
      implicitHeight: contentColumn.implicitHeight

      // PanelKeyCatcher short-circuits while a text field owns the keys, so
      // its onCloseRequested cannot be relied on for Escape. A window-scoped
      // shortcut works in every state: form, settings, and inline editing.
      Shortcut {
        sequence: "Esc"
        onActivated: root.close()
      }
      blocked: wordField.activeFocus || contextField.activeFocus || root.settingsOpen
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: contentColumn
        anchors.fill: parent
        spacing: Style.space(12)

        Row {
          width: parent.width
          spacing: Style.space(12)
          Text { width: parent.width - Style.space(170); textFormat: Text.PlainText; text: root.settingsOpen ? "WORD CAPTURE / SETTINGS" : "WORD CAPTURE"; color: root.foreground; font.family: Style.font.family; font.pixelSize: Style.font.heading; font.bold: true; elide: Text.ElideRight; anchors.verticalCenter: parent.verticalCenter }
          Button {
            width: Style.space(75)
            text: root.settingsOpen ? "BACK" : "SETTINGS"
            fontSize: Style.font.bodySmall
            foreground: root.foreground
            fontFamily: Style.font.family
            verticalPadding: Style.spacing.controlPaddingY
            bordered: true
            anchors.verticalCenter: parent.verticalCenter
            onClicked: root.settingsOpen = !root.settingsOpen
          }
          Button {
            width: Style.space(60)
            text: "CLOSE"
            fontSize: Style.font.bodySmall
            foreground: root.foreground
            fontFamily: Style.font.family
            verticalPadding: Style.spacing.controlPaddingY
            bordered: true
            anchors.verticalCenter: parent.verticalCenter
            onClicked: root.close()
          }
        }

        Column {
          visible: !root.settingsOpen
          width: parent.width
          spacing: Style.space(8)

          Text { text: "WORD / PHRASE"; color: root.dim; font.family: Style.font.family; font.pixelSize: Style.font.caption; font.bold: true }
          TextField {
            id: wordField
            width: parent.width
            focus: true
            text: root.word
            placeholderText: "Type a word or phrase"
            foreground: root.foreground
            onTextChanged: { root.word = text; root.updateDetection() }
            onAccepted: root.submit()
          }

          Text { text: "CONTEXT / EXAMPLE"; color: root.dim; font.family: Style.font.family; font.pixelSize: Style.font.caption; font.bold: true }
          TextField {
            id: contextField
            width: parent.width
            text: root.context
            placeholderText: "Meaning or an example sentence"
            foreground: root.foreground
            onTextChanged: root.context = text
            onAccepted: root.submit()
          }

          Row {
            width: parent.width
            spacing: Style.space(8)
            Text { width: parent.width - Style.space(200); text: "LANGUAGE"; color: root.dim; font.family: Style.font.family; font.pixelSize: Style.font.caption; font.bold: true; anchors.verticalCenter: parent.verticalCenter }
            Text {
              width: Style.space(192)
              text: root.matches.length ? root.matches.join(", ") : "No match"
              color: root.matches.length ? root.foreground : root.dim
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
              horizontalAlignment: Text.AlignRight
              anchors.verticalCenter: parent.verticalCenter
            }
          }
          Dropdown {
            id: languageDropdown
            width: parent.width
            showLabel: false
            value: root.language
            options: root.languages.map(function(item) { return item.name })
            onChanged: function(value) { root.language = value; root.saveState() }
          }
          // Dropdown.value becomes a local value once a user picks an option,
          // which breaks its binding to root.language. Re-apply every change
          // explicitly so detection keeps driving the visible field.
          Connections {
            target: root
            function onLanguageChanged() { languageDropdown.value = root.language }
          }

          Button {
            width: parent.width
            text: root.writing ? "SAVING" : "CAPTURE  /  ENTER"
            fontFamily: Style.font.family
            foreground: root.foreground
            fontSize: Style.font.body
            horizontalPadding: Style.spacing.controlPaddingX
            verticalPadding: Style.spacing.controlPaddingY + Style.space(2)
            bordered: true
            active: true
            enabled: !root.writing
            onClicked: root.submit()
          }
        }

        Column {
          visible: root.settingsOpen
          width: parent.width
          spacing: Style.space(10)
          Text { text: "MARKDOWN FILE"; color: root.dim; font.family: Style.font.family; font.pixelSize: Style.font.caption; font.bold: true }
          TextField { width: parent.width; text: root.filePath; foreground: root.foreground; onEditingFinished: { root.filePath = text; root.saveState() } }
          Text { text: "DISTINGUISHABLE CHARACTERS"; color: root.dim; font.family: Style.font.family; font.pixelSize: Style.font.caption; font.bold: true }
          ListView {
            width: parent.width
            // Shrink to content; only scroll once the list is genuinely tall.
            height: Math.min(contentHeight, Style.space(260))
            model: root.languages
            clip: true
            delegate: Column {
              id: langRow
              property int langIndex: index
              property string langName: modelData.name
              property string langCharacters: modelData.characters
              width: ListView.view.width
              spacing: Style.space(6)
              Row {
                width: parent.width
                spacing: Style.space(6)
                TextField {
                  id: nameField
                  width: parent.width - Style.space(180)
                  text: langRow.langName
                  foreground: root.foreground
                  onEditingFinished: {
                    if (text !== langRow.langName)
                      root.updateLanguage(langRow.langIndex, text, charactersField.text)
                  }
                }
                TextField {
                  id: charactersField
                  width: Style.space(95)
                  text: langRow.langCharacters
                  foreground: root.foreground
                  placeholderText: "Characters"
                  onEditingFinished: {
                    if (text !== langRow.langCharacters)
                      root.updateLanguage(langRow.langIndex, nameField.text, text)
                  }
                }
                Button {
                  width: Style.space(70)
                  text: "REMOVE"
                  fontSize: Style.font.bodySmall
                  foreground: root.foreground
                  fontFamily: Style.font.family
                  verticalPadding: Style.spacing.controlPaddingY
                  bordered: true
                  onClicked: root.removeLanguage(langRow.langIndex)
                }
              }
              // Live-filtered suggestions; a completed preset leaves one small pill.
              Flow {
                width: parent.width
                spacing: Style.space(6)
                Repeater {
                  model: Model.characterSuggestions(charactersField.text)
                  delegate: Button {
                    text: modelData
                    fontSize: Style.font.bodySmall
                    foreground: root.foreground
                    fontFamily: Style.font.family
                    verticalPadding: Style.spacing.controlPaddingY
                    bordered: true
                    onClicked: {
                      charactersField.text = modelData
                      root.updateLanguage(langRow.langIndex, nameField.text, modelData)
                    }
                  }
                }
              }
            }
          }
          Button {
            width: parent.width
            text: "ADD LANGUAGE"
            fontSize: Style.font.bodySmall
            foreground: root.foreground
            fontFamily: Style.font.family
            verticalPadding: Style.spacing.controlPaddingY
            bordered: true
            onClicked: { root.languages = root.languages.concat([{ name: "New language", characters: "any" }]); root.saveState() }
          }
          Text { width: parent.width; text: "Distinguishable characters decide the language: latin, cyrillic, greek, arabic, hebrew, any, or a custom class such as A-Za-zÀ-ÿ."; color: root.dim; wrapMode: Text.Wrap; font.family: Style.font.family; font.pixelSize: Style.font.caption }
        }
      }
    }
  }
}
