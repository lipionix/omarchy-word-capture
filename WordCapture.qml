import QtQuick
import QtQuick.Controls as QQC
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
  // True once the language was picked by hand for the current word; until
  // then the first matching language in list order wins.
  property bool languagePicked: false
  property bool settingsOpen: false
  property bool prefillClipboard: false
  // Which field the clipboard fills: "word" (default) or "context".
  property string prefillTarget: "word"
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
  property string themeYellow: ""
  // Nothing is read until the panel is first opened: the bar button alone
  // costs no file reads, parsing or watching.
  property bool activated: false
  // The palette's yellow marks an already-captured word; accent if the theme has none.
  readonly property color warning: themeYellow !== "" ? themeYellow : Commons.Color.accent

  // Reset view state on every open. onOpenedChanged alone proved unreliable
  // across shell restarts, so own the entry points the shell calls.
  function open() {
    activated = true
    settingsOpen = false
    error = ""
    controller.show()
    // Only an empty target field takes the clipboard, so a kept draft wins.
    var targetEmpty = prefillTarget === "context" ? !context.trim() : !word.trim()
    if (prefillClipboard && targetEmpty && !clipboardJob.running) clipboardJob.running = true
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
      if (typeof state.prefillClipboard === "boolean") prefillClipboard = state.prefillClipboard
      if (state.prefillTarget === "word" || state.prefillTarget === "context") prefillTarget = state.prefillTarget
    } catch (e) {}
  }

  function saveState() {
    stateFile.setText(JSON.stringify({ filePath: filePath, languages: languages, language: language, prefillClipboard: prefillClipboard, prefillTarget: prefillTarget }) + "\n")
  }

  function updateDetection() {
    // Detect from the word field only: mixing in context would cancel a
    // script match whenever the two fields use different alphabets.
    matches = Model.detect(word, languages)
    if (!word.trim()) languagePicked = false
    // List order is priority: the first match wins, unless a language was
    // picked by hand for this word and still matches.
    if (!matches.length) return
    if (languagePicked && matches.indexOf(language) !== -1) return
    languagePicked = false
    language = matches[0]
  }

  function moveLanguage(index, delta) {
    var target = index + delta
    if (target < 0 || target >= languages.length) return
    var next = languages.slice()
    var item = next.splice(index, 1)[0]
    next.splice(target, 0, item)
    languages = Model.normalizeLanguages(next)
    saveState()
    updateDetection()
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

  function setFilePath(path) {
    var next = Model.safeText(path, 500).trim()
    if (next === filePath) return
    filePath = next
    saveState()
  }

  // The desktop file chooser, as the built-in panels use it: close the panel
  // first (the dialog is a normal window under the panel's layer), then
  // report the result as a toast. Cancel does nothing.
  function pickFile(create) {
    if (pickJob.running) return
    var resolved = Model.resolvePath(filePath, home)
    var folder = resolved ? resolved.replace(/\/[^\/]*$/, "") || "/" : home
    pickJob.command = create
      ? ["python3", pluginDir + "/new-file.py", folder, fileName || "words.md"]
      : ["omarchy-file-select", "--title", "Words file", "--extensions", "md markdown txt"]
    close()
    pickJob.running = true
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

  FileView {
    path: root.activated ? Commons.Color.currentThemePath + "/colors.toml" : ""
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.themeYellow = Model.themeYellow(text())
    onLoadFailed: root.themeYellow = ""
  }

  // The words file, read and watched in-shell for the "Already captured" hint.
  FileView {
    id: wordsFile
    path: root.activated ? Model.resolvePath(root.filePath, root.home) : ""
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
    command: ["sh", root.pluginDir + "/append.sh", root.filePath, root.pendingEntry]
    onDone: function(ok, output, errors) { root.finish(ok, errors) }
  }

  // "-t text" asks for a text type; an image-only clipboard fails and is ignored.
  Job {
    id: clipboardJob
    command: ["wl-paste", "-n", "-t", "text"]
    onDone: function(ok, output, errors) {
      var target = root.prefillTarget
      var text = ok ? Model.clipboardText(output, target) : ""
      if (!text || !root.opened) return
      if (target === "context") {
        if (!root.context.trim()) root.context = text
        return
      }
      if (root.word.trim()) return
      root.word = text
      // Select it so typing replaces it.
      Qt.callLater(function() {
        var field = panel.loadedContent ? panel.loadedContent.wordField : null
        if (!field) return
        field.forceActiveFocus()
        field.selectAll()
      })
    }
  }

  // Exit 1 is "nothing picked"; anything else without a path is a failure.
  Job {
    id: pickJob
    onDone: function(ok, output, errors) {
      var path = output.split("\n")[0]
      if (ok && path) {
        root.setFilePath(path)
        root.notify("Words file", root.fileName)
      } else if (errors) {
        root.notify("File chooser failed", errors)
      }
    }
  }

  Job {
    id: openJob
    command: ["sh", root.pluginDir + "/append.sh", "--touch", root.filePath]
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

        // PanelHero's title and meta typography without its icon: the bar
        // already shows the glyph, and PanelHero always reserves icon space.
        Item {
          width: parent.width
          implicitHeight: Math.max(headerLabels.implicitHeight, settingsButton.implicitHeight)
          Column {
            id: headerLabels
            anchors.left: parent.left
            anchors.right: settingsButton.left
            anchors.rightMargin: Style.space(12)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)
            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: "Word capture"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
              elide: Text.ElideRight
            }
            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: (root.settingsOpen ? "Settings" : (root.fileName || "No file set")).toUpperCase()
              color: Qt.darker(root.foreground, 1.4)
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 1.2
              elide: Text.ElideRight
            }
          }
          PanelActionButton {
            id: settingsButton
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            iconText: root.settingsOpen ? "󰁍" : "󰒓"
            tooltipText: root.settingsOpen ? "Back" : "Settings"
            foreground: root.foreground
            fontFamily: root.fontFamily
            focusable: true
            onClicked: root.settingsOpen = !root.settingsOpen
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
            // Same surface as every TextField; only the border turns yellow
            // while the word is already in the file.
            background: BorderSurface {
              color: Style.controlFill(wordField._focused, wordField._hot, wordField.foreground, wordField.accent)
              borderSpec: root.alreadyCaptured
                ? Border.flat(root.warning, Math.max(1, Border.uniformWidth(wordField._borderSpec)))
                : wordField._borderSpec
              radius: Style.cornerRadius
            }
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
          // Multi-line context, styled like the shell's TextField: grows to five
          // lines, then scrolls. Enter captures, Shift+Enter adds a line.
          Flickable {
            id: contextFlick
            width: parent.width
            height: Math.min(contextField.implicitHeight,
              contextMetrics.lineSpacing * 5 + contextField.topPadding + contextField.bottomPadding)
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            QQC.TextArea.flickable: QQC.TextArea {
              id: contextField
              readonly property var _borderSpec: Border.controlSpec(activeFocus ? "focus" : (hovered ? "hover-cursor" : "normal"), root.foreground, Commons.Color.accent)
              text: root.context
              placeholderText: "Meaning or an example · Shift+Enter for a new line"
              wrapMode: TextEdit.Wrap
              hoverEnabled: true
              font.family: Style.font.family
              font.pixelSize: Style.font.body
              color: root.foreground
              selectionColor: Style.selectionFillFor(root.foreground, Commons.Color.accent)
              selectedTextColor: root.foreground
              placeholderTextColor: Qt.darker(root.foreground, 1.6)
              leftPadding: Style.spacing.controlPaddingX + Border.left(_borderSpec)
              rightPadding: Style.spacing.controlPaddingX + Border.right(_borderSpec)
              topPadding: Style.spacing.inputPaddingY + Border.top(_borderSpec)
              bottomPadding: Style.spacing.inputPaddingY + Border.bottom(_borderSpec)
              background: BorderSurface {
                color: Style.controlFill(contextField.activeFocus, contextField.hovered, root.foreground, Commons.Color.accent)
                borderSpec: contextField._borderSpec
                radius: Style.cornerRadius
              }
              onTextChanged: root.context = text
              Keys.onPressed: function(event) {
                var enter = event.key === Qt.Key_Return || event.key === Qt.Key_Enter
                if (enter && !(event.modifiers & Qt.ShiftModifier)) {
                  event.accepted = true
                  root.submit()
                } else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
                  // Tab moves on, as in the other fields, instead of typing a tab.
                  event.accepted = true
                  var back = event.key === Qt.Key_Backtab || (event.modifiers & Qt.ShiftModifier)
                  var next = contextField.nextItemInFocusChain(!back)
                  if (next) next.forceActiveFocus()
                }
              }
            }
          }
          FontMetrics { id: contextMetrics; font: contextField.font }

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
            onChanged: function(value) { root.languagePicked = true; root.language = value; root.saveState() }
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
          spacing: Style.spacing.rowGap
          PanelSectionHeader { text: "MARKDOWN FILE"; foreground: root.foreground }
          Row {
            width: parent.width
            spacing: Style.spacing.controlGap
            TextField {
              width: parent.width - pickerActions.width - parent.spacing
              text: root.filePath
              foreground: root.foreground
              onEditingFinished: root.setFilePath(text)
            }
            Row {
              id: pickerActions
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.spacing.xs
              PanelActionButton {
                iconText: "󰝰"
                tooltipText: "Choose a file"
                foreground: root.foreground
                fontFamily: root.fontFamily
                focusable: true
                enabled: !pickJob.running
                onClicked: root.pickFile(false)
              }
              PanelActionButton {
                iconText: "󰝒"
                tooltipText: "New file"
                foreground: root.foreground
                fontFamily: root.fontFamily
                focusable: true
                enabled: !pickJob.running
                onClicked: root.pickFile(true)
              }
            }
          }
          Toggle {
            width: parent.width
            label: "Prefill from clipboard"
            description: "On open, put copied text into an empty word field."
            checked: root.prefillClipboard
            foreground: root.foreground
            fontFamily: root.fontFamily
            onClicked: { root.prefillClipboard = !root.prefillClipboard; root.saveState() }
          }
          Row {
            visible: root.prefillClipboard
            width: parent.width
            spacing: Style.spacing.controlGap
            PanelSectionHeader { text: "FILL"; foreground: root.foreground; anchors.verticalCenter: parent.verticalCenter }
            // Plain bordered Buttons, like the plugin's others; the chosen one
            // carries the selected fill.
            Repeater {
              model: [{ value: "word", label: "WORD" }, { value: "context", label: "CONTEXT" }]
              delegate: Button {
                anchors.verticalCenter: parent.verticalCenter
                text: modelData.label
                fontSize: Style.font.bodySmall
                foreground: root.foreground
                verticalPadding: Style.spacing.controlPaddingY
                bordered: true
                selected: root.prefillTarget === modelData.value
                onClicked: { root.prefillTarget = modelData.value; root.saveState() }
              }
            }
          }
          PanelSectionHeader { text: "LANGUAGES"; foreground: root.foreground }
          ListView {
            width: parent.width
            // Shrink to content; only scroll once the list is genuinely tall.
            height: Math.min(contentHeight, Style.space(260))
            model: root.languages
            clip: true
            spacing: Style.spacing.rowGap
            // One line per language: name, script, remove. A custom character
            // class gets its own field under the line, only for Custom….
            delegate: Column {
              id: langRow
              property int langIndex: index
              property string langName: modelData.name
              property string langCharacters: modelData.characters
              readonly property bool storedCustom: Model.scriptLabel(langCharacters) === Model.customScript
              // Custom… picked but no class typed yet: nothing to save until there is.
              property bool customPicked: false
              readonly property bool isCustom: customPicked || storedCustom
              width: ListView.view.width
              spacing: Style.spacing.rowGap

              Row {
                width: parent.width
                spacing: Style.spacing.controlGap
                TextField {
                  id: nameField
                  width: parent.width - scriptDropdown.width - rowActions.width - parent.spacing * 2
                  text: langRow.langName
                  placeholderText: "Language"
                  foreground: root.foreground
                  onEditingFinished: {
                    if (text !== langRow.langName)
                      root.updateLanguage(langRow.langIndex, text, langRow.langCharacters)
                  }
                }
                Dropdown {
                  id: scriptDropdown
                  width: Style.space(120)
                  rowHeight: nameField.height
                  showLabel: false
                  value: langRow.isCustom ? Model.customScript : Model.scriptLabel(langRow.langCharacters)
                  options: Model.scriptLabels()
                  onChanged: function(value) {
                    if (value === Model.customScript) {
                      langRow.customPicked = true
                      Qt.callLater(function() { customField.forceActiveFocus() })
                      return
                    }
                    langRow.customPicked = false
                    root.updateLanguage(langRow.langIndex, nameField.text, Model.scriptValue(value))
                  }
                }
                // Order is priority among languages with the same script.
                Row {
                  id: rowActions
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.spacing.xs
                  PanelActionButton {
                    iconText: "󰅃"
                    tooltipText: "Higher priority"
                    foreground: root.foreground
                    fontFamily: root.fontFamily
                    focusable: true
                    enabled: langRow.langIndex > 0
                    onClicked: root.moveLanguage(langRow.langIndex, -1)
                  }
                  PanelActionButton {
                    iconText: "󰅀"
                    tooltipText: "Lower priority"
                    foreground: root.foreground
                    fontFamily: root.fontFamily
                    focusable: true
                    enabled: langRow.langIndex < root.languages.length - 1
                    onClicked: root.moveLanguage(langRow.langIndex, 1)
                  }
                  PanelActionButton {
                    iconText: "󰅖"
                    tooltipText: "Remove"
                    foreground: root.foreground
                    hoverColor: root.urgent
                    fontFamily: root.fontFamily
                    focusable: true
                    enabled: root.languages.length > 1
                    onClicked: root.removeLanguage(langRow.langIndex)
                  }
                }
              }
              TextField {
                id: customField
                visible: langRow.isCustom
                width: parent.width
                text: langRow.storedCustom ? langRow.langCharacters : ""
                placeholderText: "Character class, e.g. A-Za-zÀ-ÿ"
                foreground: root.foreground
                onEditingFinished: {
                  var value = text.trim()
                  if (value && value !== langRow.langCharacters)
                    root.updateLanguage(langRow.langIndex, nameField.text, value)
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
          Text { width: parent.width; text: "The script of the typed word picks its language; the first match in this order wins. Custom… takes a character class."; color: root.dim; wrapMode: Text.Wrap; font.family: Style.font.family; font.pixelSize: Style.font.caption }
        }
      }
    }
  }
}
