import QtQuick
import QtQuick.Controls as QQC
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Model.js" as Model

// The capture panel. WordCapture.qml (the bar button) creates it on first use
// and hands it the button to anchor against; until then nothing here exists.
Panel {
  id: root
  moduleName: "lipionix.word-capture"

  property var anchorItem: null
  // The bar tracks the widget in its slot (WordCapture.qml), not this nested
  // panel, so the popout coordinator has to see that widget as the owner.
  property var hostWidget: null
  // Nerd Font md-book_plus, the bar glyph; also the toast's icon.
  readonly property string glyph: "󰗛"

  // Settings live with the other Omarchy plugin state (XDG state dir).
  property string statePath: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/omarchy/word-capture.json"
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
  // Set on the first open of Settings, which builds them (see settingsLoader).
  property bool settingsBuilt: false
  onSettingsOpenChanged: if (settingsOpen) settingsBuilt = true
  property bool prefillClipboard: false
  // Which field the clipboard fills: "word" (default) or "context".
  property string prefillTarget: "word"
  property bool writing: false
  property string pendingEntry: ""
  property bool pendingDuplicate: false
  property string error: ""
  readonly property string pluginDir: decodeURIComponent(String(Qt.resolvedUrl(".")).replace(/^file:\/\//, "")).replace(/\/$/, "")
  readonly property color foreground: bar ? bar.foreground : Commons.Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property color urgent: bar ? bar.urgent : Commons.Color.urgent
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property string fileName: Model.fileName(filePath)
  readonly property string home: Quickshell.env("HOME")
  // The words file's index (words, counts per tag), kept live by wordsFile below.
  property var wordIndex: Model.emptyIndex()
  property bool indexLoaded: false
  // Bumped when the index changes in place (after a save), so bindings re-read it.
  property int indexVersion: 0
  readonly property bool alreadyCaptured: indexVersion >= 0 && Model.isCaptured(wordIndex, word)
  property string themeYellow: ""
  // The palette's yellow marks an already-captured word; accent if the theme has none.
  readonly property color warning: themeYellow !== "" ? themeYellow : Commons.Color.accent

  // Reset view state on every open. onOpenedChanged alone proved unreliable
  // across shell restarts, so own the entry points the shell calls.
  // Reopened after the folder chooser: Settings, path field focused, file name selected.
  property bool pathFocus: false

  function open() {
    settingsOpen = false
    pathFocus = false
    error = ""
    controller.show()
    // Only the target field takes the clipboard, and only when it is empty;
    // a draft in the other field does not matter.
    if (prefillClipboard && Model.prefillField(prefillTarget, word, context) && !clipboardJob.running)
      clipboardJob.running = true
  }
  function close() {
    settingsOpen = false
    pathFocus = false
    controller.hide()
  }
  function toggle() { opened ? close() : open() }

  function loadState(raw) {
    try {
      const state = JSON.parse(String(raw || "{}"))
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
    // Reassigned only when the list changes, so the hint row and its
    // bindings are not rebuilt on every keystroke.
    var next = Model.detect(word, languages)
    if (next.join("\n") !== matches.join("\n")) matches = next
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
    // Decide "already had it" now, before the write can reach the index.
    pendingDuplicate = alreadyCaptured
    writing = true
    appendProcess.running = true
  }

  function finish(ok, message, savedPath) {
    writing = false
    if (!ok) { error = message || "Could not write to " + filePath; return }
    // Update the in-memory index right away for the toast's counts; the file
    // single re-read below syncs it from disk.
    var stats = ""
    if (indexLoaded) {
      stats = Model.statsLine(Model.recordCapture(wordIndex, Model.normalizeWord(word), language, pendingDuplicate), language)
      indexVersion++
    }
    // Clicking the toast opens the file: the notification service runs the
    // --exec argv itself on click, so no process waits for it.
    notify("Captured " + word.trim(), stats || fileName, savedPath ? ["omarchy-launch-editor", savedPath] : null)
    // The save replaced the file (temp + rename) or created it: re-read once,
    // which also re-arms the watch on the new file. Watch events from our own
    // write are skipped until this read lands.
    ownReload = true
    wordsFile.reload()
    word = ""
    context = ""
    pendingEntry = ""
    close()
  }

  // Toasts go through omarchy-notification-send, as the built-in panels do.
  function notify(headline, description, clickArgv) {
    var argv = ["omarchy-notification-send", "-g", glyph, headline]
    if (description) argv.push(description)
    if (clickArgv) argv = argv.concat(["--exec"], clickArgv)
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

  // The desktop folder chooser (Omarchy's own helper). The panel is a
  // full-screen overlay layer that holds the keyboard, so the dialog (a normal
  // window) would open underneath it: close the panel for the chooser, then
  // reopen it in Settings once the chooser returns, pick or cancel. The file
  // name is kept; only its folder changes.
  function reopenForPath() {
    error = ""
    settingsOpen = true
    pathFocus = true
    controller.show()
  }

  function pickFolder() {
    if (pickJob.running) return
    pickJob.command = ["omarchy-file-select", "--title", "Folder for " + (fileName || "words.md"), "--directory"]
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
    // Read in place on creation: the panel is created by the first click,
    // and that open() already needs the settings (file, prefill).
    blockLoading: true
    printErrors: false
  }
  Component.onCompleted: loadState(stateFile.text())

  FileView {
    path: Commons.Color.currentThemePath + "/colors.toml"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.themeYellow = Model.themeYellow(text())
    onLoadFailed: root.themeYellow = ""
  }

  // Set while our own save's re-read is pending (see finish()).
  property bool ownReload: false

  // The words file, read and watched in-shell for the "Already captured" hint.
  FileView {
    id: wordsFile
    path: root.resolvedFilePath
    watchChanges: true
    printErrors: false
    // An outside edit re-reads; our own write is read once by finish().
    onFileChanged: if (!root.writing && !root.ownReload) reload()
    onPathChanged: root.indexLoaded = false
    onLoaded: { root.ownReload = false; root.wordIndex = Model.wordIndex(text()); root.indexLoaded = true; root.fileMissing = false }
    onLoadFailed: function(error) {
      root.ownReload = false
      root.wordIndex = Model.emptyIndex()
      root.indexLoaded = true
      root.fileMissing = root.notFound(error)
    }
  }

  // "New file" hint. The saved path's state comes from wordsFile above; while
  // the path field is being edited, a second FileView probes the typed path,
  // 200 ms after the last keystroke. No processes, one probe at a time.
  property bool fileMissing: false
  property string probePath: ""
  property bool probeMissing: false
  readonly property string resolvedFilePath: Model.resolvePath(filePath, home)
  readonly property bool probing: probePath !== "" && probePath !== resolvedFilePath
  readonly property bool pathMissing: probing ? probeMissing : fileMissing
  // A saved path the probe already checked keeps its answer until wordsFile reloads.
  onFilePathChanged: {
    if (probePath !== "" && probePath === resolvedFilePath) fileMissing = probeMissing
    probePath = ""
  }
  function notFound(error) {
    return typeof FileViewError === "undefined" || error === FileViewError.FileNotFound
  }
  Timer {
    id: probeTimer
    interval: 200
    property string draft: ""
    onTriggered: root.probePath = Model.resolvePath(draft, root.home)
  }
  FileView {
    path: root.probing ? root.probePath : ""
    printErrors: false
    onLoaded: root.probeMissing = false
    onLoadFailed: function(error) { root.probeMissing = root.notFound(error) }
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
    // The entry goes to the end of its "## <language>" section.
    command: ["sh", root.pluginDir + "/append.sh", root.filePath, root.pendingEntry, root.language]
    onDone: function(ok, output, errors) { root.finish(ok, errors, output.split("\n")[0]) }
  }

  // "-t text" asks for a text type; an image-only clipboard fails and is ignored.
  Job {
    id: clipboardJob
    command: ["wl-paste", "-n", "-t", "text"]
    onDone: function(ok, output, errors) {
      var target = root.prefillTarget
      var text = ok ? Model.clipboardText(output, target) : ""
      if (!text || !root.opened) return
      // Recheck: the target may have been typed into while wl-paste ran.
      if (Model.prefillField(target, root.word, root.context) !== target) return
      if (target === "context") root.context = text
      else root.word = text
      // Focus the other field, ready to type: word filled -> context, and the
      // other way round.
      Qt.callLater(function() {
        var content = panel.loadedContent
        var field = content ? (target === "context" ? content.wordField : content.contextField) : null
        if (!field) return
        field.forceActiveFocus()
        if (field.cursorPosition !== undefined) field.cursorPosition = field.text.length
      })
    }
  }

  // Exit 1 is "nothing picked"; anything else without a path is a failure.
  Job {
    id: pickJob
    onDone: function(ok, output, errors) {
      var picked = output.split("\n")[0]
      var folder = picked.replace(/\/+$/, "")  // "/" becomes "", then "/name"
      if (ok && picked) {
        root.setFilePath(folder + "/" + (root.fileName || "words.md"))
      } else if (errors) {
        root.notify("File chooser failed", errors)
      }
      root.reopenForPath()
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

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.hostWidget || root
    bar: root.bar
    open: root.opened
    // The content stays loaded between opens, so focus the word field on
    // every open rather than once at creation.
    focusTarget: panel.loadedContent
      ? (root.pathFocus ? panel.loadedContent.pathField : panel.loadedContent.wordField)
      : null
    contentWidth: panel.fittedContentWidth(Style.space(420))
    // Follow the content, never a fixed height: fixed heights leave dead space.
    contentHeight: panel.fittedContentHeight(panel.loadedContentHeight, Style.space(620))

    content: PanelKeyCatcher {
      id: keyCatcher
      property alias wordField: wordField
      readonly property var pathField: settingsLoader.item ? settingsLoader.item.pathField : null
      property alias contextField: contextField
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
              id: metaLine
              // The file name opens the file (as right-click on the bar icon does).
              readonly property bool isLink: !root.settingsOpen && root.fileName !== ""
              width: parent.width
              textFormat: Text.PlainText
              text: (root.settingsOpen ? "Settings" : (root.fileName ? root.fileName + (root.fileMissing ? " (new)" : "") : "No file set")).toUpperCase()
              color: Qt.darker(root.foreground, 1.4)
              font.underline: isLink && metaLink.containsMouse
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 1.2
              elide: Text.ElideRight
              MouseArea {
                id: metaLink
                // Only the file name itself, and only in the main view: a
                // disabled MouseArea still sets its cursor, so hide it instead.
                width: Math.min(parent.contentWidth, parent.width)
                height: parent.height
                visible: metaLine.isLink
                enabled: metaLine.isLink
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: { root.close(); root.openFile() }
              }
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
              // Full theme yellow at the field's own border width. The shell's
              // control states fade a border to 40-60% alpha, which hides it.
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

          PanelSectionHeader { text: "CONTEXT / NOTE"; foreground: root.foreground }
          // Multi-line context, styled like the shell's TextField: grows to five
          // lines, then scrolls. Enter captures, Shift+Enter adds a line.
          Flickable {
            id: contextFlick
            width: parent.width
            // Height from the typed text only (one line when empty), up to
            // five lines, then it scrolls.
            height: Math.min(Math.max(contextField.contentHeight, contextMetrics.lineSpacing), contextMetrics.lineSpacing * 5)
              + contextField.topPadding + contextField.bottomPadding
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            QQC.TextArea.flickable: QQC.TextArea {
              id: contextField
              readonly property var _borderSpec: Border.controlSpec(activeFocus ? "focus" : (hovered ? "hover-cursor" : "normal"), root.foreground, Commons.Color.accent)
              text: root.context
              // Own one-line placeholder: the control's placeholder wraps and
              // counts in the implicit height.
              Text {
                x: contextField.leftPadding
                y: contextField.topPadding
                width: contextField.width - contextField.leftPadding - contextField.rightPadding
                visible: !contextField.length && !contextField.preeditText
                textFormat: Text.PlainText
                text: "Context, example or note"
                elide: Text.ElideRight
                wrapMode: Text.NoWrap
                maximumLineCount: 1
                color: contextField.placeholderTextColor
                font: contextField.font
              }
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
                  const back = event.key === Qt.Key_Backtab || (event.modifiers & Qt.ShiftModifier)
                  const next = contextField.nextItemInFocusChain(!back)
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
            // Matching languages as links: a click picks one, and it sticks
            // for this word like a pick in the dropdown.
            Item {
              width: Style.space(192)
              height: matchRow.height
              anchors.verticalCenter: parent.verticalCenter
              clip: true
              Text {
                anchors.right: parent.right
                visible: !root.matches.length
                textFormat: Text.PlainText
                text: "No match"
                color: root.dim
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
              }
              Row {
                id: matchRow
                anchors.right: parent.right
                Repeater {
                  model: root.matches
                  delegate: Row {
                    id: matchItem
                    required property string modelData
                    required property int index
                    Text {
                      textFormat: Text.PlainText
                      text: matchItem.modelData
                      color: matchItem.modelData === root.language || matchLink.containsMouse ? root.foreground : root.dim
                      font.family: Style.font.family
                      font.pixelSize: Style.font.caption
                      font.underline: matchLink.containsMouse
                      MouseArea {
                        id: matchLink
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                          root.languagePicked = true
                          root.language = matchItem.modelData
                          root.saveState()
                        }
                      }
                    }
                    Text {
                      visible: matchItem.index < root.matches.length - 1
                      textFormat: Text.PlainText
                      text: ", "
                      color: root.dim
                      font.family: Style.font.family
                      font.pixelSize: Style.font.caption
                    }
                  }
                }
              }
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

        // Settings are built the first time they are opened, then kept.
        Loader {
          id: settingsLoader
          width: parent.width
          active: root.settingsBuilt
          visible: root.settingsOpen
          sourceComponent: Component {
            Column {
              property alias pathField: pathField
              width: parent ? parent.width : 0
              spacing: Style.spacing.rowGap
              // Header row like LANGUAGE: the "new file" hint sits on the right.
              Row {
                width: parent.width
                spacing: Style.space(8)
                PanelSectionHeader { width: parent.width - Style.space(200); text: "MARKDOWN FILE"; foreground: root.foreground; anchors.verticalCenter: parent.verticalCenter }
                Text {
                  width: Style.space(192)
                  // Opacity, not visibility: the row keeps its height either way.
                  opacity: root.pathMissing ? 1 : 0
                  textFormat: Text.PlainText
                  text: "Created on first capture"
                  color: root.dim
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                  elide: Text.ElideRight
                  horizontalAlignment: Text.AlignRight
                  anchors.verticalCenter: parent.verticalCenter
                }
              }
              Row {
                width: parent.width
                spacing: Style.spacing.controlGap
                TextField {
                  id: pathField
                  width: parent.width - folderButton.width - parent.spacing
                  text: root.filePath
                  foreground: root.foreground
                  onEditingFinished: root.setFilePath(text)
                  onTextChanged: if (activeFocus) { probeTimer.draft = text; probeTimer.restart() }
                  // After the folder chooser: select the file name (not its
                  // extension) so typing renames just the file.
                  onActiveFocusChanged: if (activeFocus && root.pathFocus) {
                    var range = Model.nameRange(text)
                    select(range[0], range[1])
                  }
                }
                PanelActionButton {
                  id: folderButton
                  anchors.verticalCenter: parent.verticalCenter
                  iconText: "󰉖"
                  tooltipText: "Choose folder"
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  focusable: true
                  enabled: !pickJob.running
                  onClicked: root.pickFolder()
                }
              }
              Toggle {
                width: parent.width
                // Sized by the longer description (the hidden twin below), so
                // switching Word/Context never changes the row's height.
                height: prefillSizer.implicitHeight
                label: "Prefill from clipboard"
                description: root.prefillTarget === "context" ? prefillSizer.description : "Fills an empty word field on open."
                checked: root.prefillClipboard
                foreground: root.foreground
                fontFamily: root.fontFamily
                onClicked: { root.prefillClipboard = !root.prefillClipboard; root.saveState() }
              }
              Toggle {
                id: prefillSizer
                visible: false
                width: parent.width
                label: "Prefill from clipboard"
                description: "Fills an empty context field on open."
                fontFamily: root.fontFamily
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
  }
}
