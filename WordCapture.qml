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
  property string error: ""
  readonly property string pluginDir: decodeURIComponent(String(Qt.resolvedUrl(".")).replace(/^file:\/\//, "")).replace(/\/$/, "")
  readonly property color foreground: bar ? bar.foreground : Commons.Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property color urgent: bar ? bar.urgent : Commons.Color.urgent
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property string fileName: Model.fileName(filePath)
  readonly property string home: Quickshell.env("HOME")
  // Normalized words already in the file, kept live by wordsFile below.
  property var captured: ({})
  readonly property bool alreadyCaptured: Model.isCaptured(captured, word)

  // Reset view state on every open. onOpenedChanged alone proved unreliable
  // across shell restarts, so own the entry points the shell calls.
  function open() {
    settingsOpen = false
    error = ""
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
    if (writing || !word.trim()) return
    if (!filePath.trim()) { error = "Set a Markdown file in Settings."; return }
    error = ""
    pendingEntry = Model.entryLine({ text: word, note: context, tag: language })
    writing = true
    appendProcess.running = true
  }

  function finish(ok, message) {
    writing = false
    if (!ok) { error = message || "Could not write to " + filePath; return }
    notify("Captured " + word.trim(), fileName)
    // A file created by this capture had nothing to watch before it existed.
    wordsFile.reload()
    word = ""
    context = ""
    pendingEntry = ""
    close()
  }

  // Toasts go through omarchy-notification-send, as the built-in panels do.
  function notify(headline, description) {
    var argv = ["omarchy-notification-send", "-g", button.text, headline]
    if (description) argv.push(description)
    Util.execArgv(argv)
  }

  // Right-click: open the words file in the Omarchy default editor, creating
  // it first so a fresh setup opens an empty file instead of failing.
  function openFile() {
    if (openJob.running) return
    if (!filePath.trim()) { notify("Word capture", "Set a Markdown file in Settings."); return }
    openJob.running = true
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

  // The words file, read and watched in-shell for the "Already captured" hint.
  FileView {
    id: wordsFile
    path: Model.resolvePath(root.filePath, root.home)
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.captured = Model.capturedWords(text())
    onLoadFailed: root.captured = ({})
  }

  // A Process that reports once it has exited AND both streams have ended:
  // the three arrive in no guaranteed order.
  component Job: Process {
    id: job
    signal done(bool ok, string output, string errors)
    property int exitCode: -1
    property int streamsDone: 0
    function settle() {
      if (exitCode < 0 || streamsDone < 2) return
      var ok = exitCode === 0
      exitCode = -1
      streamsDone = 0
      done(ok, String(outCollector.text || "").trim(), String(errCollector.text || "").trim())
    }
    stdout: StdioCollector { id: outCollector; waitForEnd: true; onStreamFinished: { job.streamsDone++; job.settle() } }
    stderr: StdioCollector { id: errCollector; waitForEnd: true; onStreamFinished: { job.streamsDone++; job.settle() } }
    onExited: function(code) { exitCode = code; settle() }
  }

  Job {
    id: appendProcess
    command: ["python3", root.pluginDir + "/append.py", root.filePath, root.pendingEntry]
    onDone: function(ok, output, errors) { root.finish(ok, errors) }
  }

  Job {
    id: openJob
    command: ["python3", root.pluginDir + "/append.py", "--touch", root.filePath]
    onDone: function(ok, output, errors) {
      if (ok) Util.execArgv(["omarchy-launch-editor", output])
      else root.notify("Could not open " + root.fileName, errors)
    }
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
      if (buttonCode === Qt.RightButton) root.openFile()
      else if (buttonCode !== Qt.MiddleButton) root.toggle()
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

        // Same header as the built-in panels: the bar glyph, a title, and the
        // target file as the meta line. Esc or a click outside closes.
        PanelHero {
          width: parent.width
          title: "Word capture"
          meta: root.settingsOpen ? "Settings" : (root.fileName || "No file set")
          foreground: root.foreground
          fontFamily: root.fontFamily
          iconComponent: Component {
            Text {
              textFormat: Text.PlainText
              text: button.text
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.display
            }
          }
          trailingControl: Component {
            PanelActionButton {
              iconText: root.settingsOpen ? "󰁍" : "󰒓"
              tooltipText: root.settingsOpen ? "Back" : "Settings"
              foreground: root.foreground
              fontFamily: root.fontFamily
              focusable: true
              onClicked: root.settingsOpen = !root.settingsOpen
            }
          }
        }

        Column {
          visible: !root.settingsOpen
          width: parent.width
          spacing: Style.space(8)

          PanelSectionHeader { text: "WORD / PHRASE"; foreground: root.foreground }
          TextField {
            id: wordField
            width: parent.width
            focus: true
            text: root.word
            placeholderText: "Type a word or phrase"
            foreground: root.foreground
            onTextChanged: { root.word = text; root.error = ""; root.updateDetection() }
            onAccepted: root.submit()
          }
          // Saving stays allowed: the same word with new context is fine.
          Text {
            visible: root.alreadyCaptured
            textFormat: Text.PlainText
            text: "Already captured"
            color: root.dim
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }

          PanelSectionHeader { text: "CONTEXT / EXAMPLE"; foreground: root.foreground }
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
            PanelSectionHeader { width: parent.width - Style.space(200); text: "LANGUAGE"; foreground: root.foreground; anchors.verticalCenter: parent.verticalCenter }
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
            foreground: root.foreground
            fontSize: Style.font.body
            horizontalPadding: Style.spacing.controlPaddingX
            verticalPadding: Style.spacing.controlPaddingY + Style.space(2)
            bordered: true
            active: true
            enabled: !root.writing
            onClicked: root.submit()
          }
          Text {
            visible: root.error !== ""
            width: parent.width
            textFormat: Text.PlainText
            text: root.error
            color: root.urgent
            wrapMode: Text.Wrap
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
          }
        }

        Column {
          visible: root.settingsOpen
          width: parent.width
          spacing: Style.space(10)
          PanelSectionHeader { text: "MARKDOWN FILE"; foreground: root.foreground }
          TextField { width: parent.width; text: root.filePath; foreground: root.foreground; onEditingFinished: { root.filePath = text; root.saveState() } }
          PanelSectionHeader { text: "DISTINGUISHABLE CHARACTERS"; foreground: root.foreground }
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
