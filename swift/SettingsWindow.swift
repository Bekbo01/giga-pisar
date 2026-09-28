// Settings: a regular macOS settings window with tabs in the toolbar
// (General, Brain, Edit Selection, About). The menu-bar menu keeps only what
// is used every day; everything else lives here. Every change applies at once,
// and the menu and this window always show the same state (App.settingsChanged).

import AppKit
import ServiceManagement

final class SettingsWindow: NSObject, NSWindowDelegate {
    enum Tab: Int, CaseIterable { case general, brain, edit, about }

    private weak var app: App?
    private var window: NSWindow?
    private var tabs: NSTabViewController?
    private var targets: [ActionTarget] = []   // controls keep their targets weakly
    private var cloud: CloudBrainPanel?
    private var downloadLabel: NSTextField?
    private let width: CGFloat = 540

    init(app: App) {
        self.app = app
        super.init()
    }

    var isVisible: Bool { window?.isVisible == true }

    func show(tab: Tab? = nil) {
        if window == nil { makeWindow() }
        if let tab { select(tab) }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(nil)   // no field grabs focus (a selected key field looks alarming)
    }

    /// Rebuilds the pages from the current state, keeping the open tab.
    /// keepBrain: the cloud panel saved itself; its status line must stay.
    func refresh(keepBrain: Bool = false) {
        guard let tabs, isVisible else { return }
        let current = tabs.selectedTabViewItemIndex
        fillTabs(keepBrain: keepBrain)
        tabs.selectedTabViewItemIndex = max(0, current)
    }

    /// Only the "downloading N%" line: the page is not rebuilt on every percent.
    func updateDownload() {
        guard let downloadLabel, let id = Brain.shared.downloadingId,
              let m = BRAIN_MODELS.first(where: { $0.id == id }) else { refresh(); return }
        downloadLabel.stringValue = L("Качаю \(m.name): \(Brain.shared.downloadPercent)%",
                                      "Downloading \(m.name): \(Brain.shared.downloadPercent)%")
    }

    // MARK: window

    private func makeWindow() {
        let tabs = NSTabViewController()
        tabs.tabStyle = .toolbar
        tabs.transitionOptions = [.allowUserInteraction]
        self.tabs = tabs
        let w = NSWindow(contentViewController: tabs)
        w.styleMask = [.titled, .closable, .miniaturizable]
        w.title = L("Гига Писарь: настройки", "Giga Pisar Settings")
        w.isReleasedWhenClosed = false
        w.delegate = self
        window = w
        fillTabs()
        select(Tab(rawValue: UserDefaults.standard.integer(forKey: "settingsTab")) ?? .general)
        w.center()
    }

    private func select(_ tab: Tab) {
        tabs?.selectedTabViewItemIndex = tab.rawValue
        UserDefaults.standard.set(tab.rawValue, forKey: "settingsTab")
    }

    func windowWillClose(_ notification: Notification) {
        if let i = tabs?.selectedTabViewItemIndex { UserDefaults.standard.set(i, forKey: "settingsTab") }
    }

    private func fillTabs(keepBrain: Bool = false) {
        guard let tabs else { return }
        let oldBrain = keepBrain && tabs.tabViewItems.count > Tab.brain.rawValue
            ? tabs.tabViewItems[Tab.brain.rawValue].viewController?.view : nil
        if oldBrain == nil {
            targets.removeAll()
            downloadLabel = nil
        }
        let pages: [(String, String, NSView)] = [
            (L("Основные", "General"), "gearshape", generalPage()),
            (L("Мозг", "Brain"), "brain", oldBrain ?? brainPage()),
            (L("Правка выделенного", "Edit Selection"), "character.cursor.ibeam", editPage()),
            (L("О программе", "About"), "info.circle", aboutPage()),
        ]
        while !tabs.tabViewItems.isEmpty { tabs.removeTabViewItem(tabs.tabViewItems[0]) }
        for (title, icon, view) in pages {
            let vc = NSViewController()
            vc.view = view
            vc.title = title   // the window title follows the open tab, as in macOS settings
            vc.preferredContentSize = view.fittingSize
            let item = NSTabViewItem(viewController: vc)
            item.label = title
            item.image = NSImage(systemSymbolName: icon, accessibilityDescription: title)
            tabs.addTabViewItem(item)
        }
    }

    // MARK: pages

    private func generalPage() -> NSView {
        guard let app else { return NSView() }
        let key = popup(HOTKEYS.map { ($0.id, $0.title) }, selected: currentHotkey().id) { app.selectHotkey($0) }
        let wave = popup([("off", L("Выключена", "Off")), ("cursor", L("У курсора", "Near cursor")),
                          ("bottom", L("Внизу экрана", "Bottom of screen"))],
                         selected: app.waveChoice) { app.selectWave($0) }
        let lang = popup([("auto", L("Как в системе", "Same as system")), ("ru", "Русский"), ("en", "English")],
                         selected: UserDefaults.standard.string(forKey: "uiLang") ?? "auto") { app.selectLang($0) }
        let hush = checkbox(L("Приглушать звук во время диктовки", "Mute sound while dictating"),
                            on: Sound.muteWhileDictating) { _ in app.toggleHush() }
        let login = checkbox(L("Запускать при входе в систему", "Open at login"),
                             on: SMAppService.mainApp.status == .enabled) { _ in app.toggleLogin() }
        let access = button(L("Доступы…", "Permissions…")) { app.showOnboarding() }
        let grid = form([
            (L("Клавиша диктовки:", "Dictation key:"), key),
            (L("Волна голоса:", "Voice wave:"), wave),
            (L("Язык:", "Language:"), lang),
            ("", hush),
            ("", login),
            ("", access),
        ])
        return page(L("Зажми клавишу, говори, отпусти: текст появится там, где курсор.",
                      "Hold the key, speak, release: the text appears at the cursor."), [grid])
    }

    private func brainPage() -> NSView {
        guard let app else { return NSView() }
        let b = Brain.shared
        var items: [(String, String)] = [("off", L("Выключен", "Off"))]
        for m in BRAIN_MODELS where b.engineAvailable {
            let t: String
            if b.downloadingId == m.id { t = L("\(m.name) (качаю \(b.downloadPercent)%)", "\(m.name) (downloading \(b.downloadPercent)%)") }
            else if !b.downloaded(m) { t = L("\(m.name) (скачать \(m.sizeText))", "\(m.name) (download \(m.sizeText))") }
            else { t = L("\(m.name) на этом маке", "\(m.name) on this Mac") }
            items.append((m.id, t))
        }
        items.append((BrainServer.id, L("В облаке", "In the cloud")))
        let current = b.chosenId ?? "off"
        let choice = popup(items, selected: current) { id in
            guard id != current else { return }
            app.selectBrain(id)
            self.refresh()   // a declined download puts the old choice back
        }

        var rows: [(String, NSView)] = [(L("Где думает:", "Runs on:"), choice)]
        if let id = b.downloadingId, BRAIN_MODELS.contains(where: { $0.id == id }) {
            let label = small("")
            downloadLabel = label
            let cancel = button(L("Отменить", "Cancel")) { b.cancelDownload() }
            let row = NSStackView(views: [label, cancel])
            row.spacing = 10
            rows.append(("", row))
            DispatchQueue.main.async { self.updateDownload() }
        } else if let m = b.chosenModel {
            rows.append(("", small(b.detailsText(m))))
        } else if !b.engineAvailable {
            rows.append(("", small(L("Нейросети на этом маке работают только на M-чипах. В облаке работает на любом.",
                                     "On-device models need Apple Silicon. The cloud works on any Mac."))))
        }

        var parts: [NSView] = [form(rows)]
        if b.usesServer {
            let panel = CloudBrainPanel { [weak self] in
                app.buildMenu()
                self?.refresh(keepBrain: true)
            }
            cloud = panel
            parts.append(panel.view)
        } else {
            cloud = nil
        }

        let every = checkbox(L("Править каждую диктовку, без команды", "Edit every take, without a command"),
                             on: b.everyTake, enabled: b.ready) { _ in app.toggleEveryTake() }
        let menuMode = radio(L("Менюшка у курсора: причесать, сократить, перевести",
                               "A menu at the cursor: tidy, shorten, translate"),
                             on: b.chipsEnabled, enabled: b.ready) { app.setChipsMenu(true) }
        let voiceMode = radio(L("Только голосом: «…Писарь, исправь»", "Voice only: “…Pisar, fix this”"),
                              on: !b.chipsEnabled, enabled: b.ready) { app.setChipsMenu(false) }
        let help = button(L("Как пользоваться…", "How to use it…")) { app.showBrainHelp() }
        parts.append(form([("", every), (L("Команды:", "Commands:"), menuMode), ("", voiceMode), ("", help)]))

        return page(L("Нейросеть правит надиктованное по команде. Скажи в конце: «Писарь, исправь», «Писарь, сократи» или «Писарь, переведи на английский». Без обращения текст вставляется сразу.",
                      "An AI model edits the dictation on command. End with “Pisar, fix this”, “Pisar, make it shorter” or “Pisar, translate to English” (in Russian). Without the address the text goes in at once."),
                    parts)
    }

    private func editPage() -> NSView {
        guard let app else { return NSView() }
        let b = Brain.shared
        let toggle = checkbox(L("Править выделенный текст голосом", "Edit selected text by voice"),
                              on: b.onSelection, enabled: b.ready) { _ in app.toggleEditSelection() }
        let off = wrap(L("Выключи, если хочешь просто диктовать поверх выделенного: тогда выделение ни на что не влияет.",
                         "Turn off to simply dictate over a selection: then selecting changes nothing."), secondary: true)
        off.font = .systemFont(ofSize: 11)
        let examplesTitle = NSTextField(labelWithString: L("Что можно сказать", "What you can say"))
        examplesTitle.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
        let examples = wrap(L("«сделай короче» · «исправь ошибки» · «перепиши вежливее»\n«переведи на английский» · «сделай списком» · «добавь заголовок»",
                              "“make it shorter” · “fix the mistakes” · “make it more polite”\n“translate to English” · “make it a list” · “add a title” (in Russian)"))
        let who: String
        if !b.ready {
            who = L("Текст переписывает нейросеть, поэтому для правки нужен Мозг. Сейчас он не выбран или не настроен.",
                    "An AI model rewrites the text, so editing needs the Brain. It is not chosen or not set up yet.")
        } else if b.usesServer {
            who = L("Переписывает Мозг в облаке: \(BrainServer.host). Выделенный текст уходит туда, звук нет.",
                    "Rewritten by the Brain in the cloud: \(BrainServer.host). The selected text goes there, audio does not.")
        } else {
            who = L("Переписывает Мозг на этом маке, без интернета.", "Rewritten by the Brain on this Mac, offline.")
        }
        let goBrain = button(b.ready ? L("Мозг…", "Brain…") : L("Настроить Мозг", "Set Up the Brain")) { [weak self] in
            self?.select(.brain)
        }
        let whoLabel = wrap(who)
        let box = NSStackView(views: [whoLabel, goBrain])
        box.orientation = .horizontal
        box.alignment = .centerY
        box.spacing = 12
        whoLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return page(L("Выдели текст в любой программе, зажми клавишу диктовки и скажи, что с ним сделать. Результат встанет на место выделенного, ⌘Z вернёт как было.",
                      "Select text in any app, hold the dictation key and say what to do with it. The result replaces the selection; ⌘Z brings it back."),
                    [toggle, off, spacer(6), examplesTitle, examples, spacer(6), box])
    }

    private func aboutPage() -> NSView {
        guard let app else { return NSView() }
        let icon = NSImageView(image: NSApp.applicationIconImage)
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 64).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 64).isActive = true
        let name = NSTextField(labelWithString: L("Гига Писарь \(APP_VERSION)", "Giga Pisar \(APP_VERSION)"))
        name.font = .boldSystemFont(ofSize: 15)
        let tagline = small(L("Распознавание идёт на этом маке, звук никуда не уходит.",
                              "Speech is recognized on this Mac; audio never leaves it."))
        let head = NSStackView(views: [icon, NSStackView(views: [name, tagline])])
        (head.views[1] as? NSStackView)?.orientation = .vertical
        (head.views[1] as? NSStackView)?.alignment = .leading
        head.spacing = 14

        let update: NSView
        if SelfUpdate.inProgress, let v = SelfUpdate.version {
            update = button(L("Качаю версию \(v)…", "Downloading version \(v)…")) { app.startSelfUpdate() }
        } else if let v = app.updateAvailable {
            update = button(L("Обновить до \(v)", "Update to \(v)")) { app.startSelfUpdate() }
        } else {
            update = button(L("Проверить обновления", "Check for Updates")) { app.checkUpdatesManual() }
        }
        let share = button(L("Рассказать другу…", "Tell a Friend…")) { app.shareApp() }
        let buttons = NSStackView(views: [update, share])
        buttons.spacing = 10
        let links = NSStackView(views: [
            link("gigapisar.github.io", "https://gigapisar.github.io"),
            link(L("исходный код", "source code"), "https://github.com/moznoazachem/giga-pisar"),
        ])
        links.spacing = 16
        return page(nil, [head, spacer(4), buttons, links])
    }

    // MARK: building blocks

    private func page(_ intro: String?, _ parts: [NSView]) -> NSView {
        var views: [NSView] = []
        if let intro { views.append(wrap(intro, secondary: true)) }
        views += parts
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 24, bottom: 22, right: 24)
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.widthAnchor.constraint(equalToConstant: width).isActive = true
        for v in views where v is NSTextField {
            v.widthAnchor.constraint(lessThanOrEqualToConstant: width - 48).isActive = true
        }
        let container = NSView()
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        container.frame.size = container.fittingSize
        return container
    }

    private func form(_ rows: [(String, NSView)]) -> NSGridView {
        let grid = NSGridView(views: rows.map { label, view in
            let l = NSTextField(labelWithString: label)
            l.alignment = .right
            return [l, view]
        })
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 0).width = 150
        grid.rowAlignment = .firstBaseline
        grid.rowSpacing = 9
        grid.columnSpacing = 10
        return grid
    }

    private func target(_ f: @escaping (Any?) -> Void) -> ActionTarget {
        let t = ActionTarget(f)
        targets.append(t)
        return t
    }

    private func popup(_ items: [(String, String)], selected: String, _ pick: @escaping (String) -> Void) -> NSPopUpButton {
        let p = NSPopUpButton()
        for (id, title) in items {
            p.addItem(withTitle: title)
            p.lastItem?.representedObject = id
        }
        if let i = items.firstIndex(where: { $0.0 == selected }) { p.selectItem(at: i) }
        let t = target { sender in
            if let id = (sender as? NSPopUpButton)?.selectedItem?.representedObject as? String { pick(id) }
        }
        p.target = t
        p.action = #selector(ActionTarget.fire(_:))
        return p
    }

    private func checkbox(_ title: String, on: Bool, enabled: Bool = true, _ toggled: @escaping (Bool) -> Void) -> NSButton {
        let t = target { sender in toggled((sender as? NSButton)?.state == .on) }
        let c = NSButton(checkboxWithTitle: title, target: t, action: #selector(ActionTarget.fire(_:)))
        c.state = on ? .on : .off
        c.isEnabled = enabled
        return c
    }

    private func radio(_ title: String, on: Bool, enabled: Bool, _ picked: @escaping () -> Void) -> NSButton {
        let t = target { _ in picked() }
        let r = NSButton(radioButtonWithTitle: title, target: t, action: #selector(ActionTarget.fire(_:)))
        r.state = on ? .on : .off
        r.isEnabled = enabled
        return r
    }

    private func button(_ title: String, _ pressed: @escaping () -> Void) -> NSButton {
        let t = target { _ in pressed() }
        return NSButton(title: title, target: t, action: #selector(ActionTarget.fire(_:)))
    }

    private func link(_ title: String, _ url: String) -> NSButton {
        let b = button(title) { if let u = URL(string: url) { NSWorkspace.shared.open(u) } }
        b.isBordered = false
        b.contentTintColor = .linkColor
        return b
    }

    private func small(_ s: String) -> NSTextField {
        let t = NSTextField(labelWithString: s)
        t.font = .systemFont(ofSize: 11)
        t.textColor = .secondaryLabelColor
        return t
    }

    private func wrap(_ s: String, secondary: Bool = false) -> NSTextField {
        let t = NSTextField(wrappingLabelWithString: s)
        if secondary { t.textColor = .secondaryLabelColor }
        t.preferredMaxLayoutWidth = width - 48
        return t
    }

    private func spacer(_ h: CGFloat) -> NSView {
        let v = NSView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.heightAnchor.constraint(equalToConstant: h).isActive = true
        return v
    }
}

/// Target/action as a closure, for controls built in code.
final class ActionTarget: NSObject {
    private let handler: (Any?) -> Void
    init(_ handler: @escaping (Any?) -> Void) { self.handler = handler }
    @objc func fire(_ sender: Any?) { handler(sender) }
}

// MARK: - the cloud Brain, inline on the Brain tab

/// Pick the service, paste the key, the model is chosen and checked. Like the rest of
/// Settings it saves by itself as soon as the set is usable; there is no Save button.
final class CloudBrainPanel: NSObject, NSTextFieldDelegate, NSComboBoxDelegate {
    let view: NSView
    private let service = NSPopUpButton()
    private let key = NSSecureTextField()
    private let keysLink = NSButton()
    private let url = NSTextField()
    private let model = NSComboBox()
    private let reload = NSButton()
    private let status = NSTextField(wrappingLabelWithString: "")
    private var grid: NSGridView!
    private var pause: Timer?
    private var serial = 0
    private var lastProviderId = ""
    private let saved: () -> Void

    private var provider: BrainProvider { BrainProviders.all[max(0, service.indexOfSelectedItem)] }
    private var endpoint: String { provider.isCustom ? url.stringValue.trimmingCharacters(in: .whitespaces) : provider.baseURL }

    init(saved: @escaping () -> Void) {
        self.saved = saved
        view = NSView()
        super.init()
        build()
    }

    private func build() {
        for p in BrainProviders.all { service.addItem(withTitle: BrainProviders.title(p)) }
        let current = BrainServer.baseURL.isEmpty ? BrainProviders.deepseek : BrainProviders.fromURL(BrainServer.baseURL)
        service.selectItem(at: BrainProviders.all.firstIndex { $0.id == current.id } ?? 0)
        lastProviderId = current.id
        service.target = self
        service.action = #selector(serviceChanged)

        key.stringValue = BrainServer.apiKey
        key.placeholderString = L("вставь ключ", "paste the key")
        key.toolTip = L("Хранится в Связке ключей", "Kept in the Keychain")
        key.delegate = self

        keysLink.bezelStyle = .inline
        keysLink.isBordered = false
        keysLink.contentTintColor = .linkColor
        keysLink.font = .systemFont(ofSize: 11)
        keysLink.target = self
        keysLink.action = #selector(openKeys)

        url.stringValue = current.isCustom ? BrainServer.baseURL : ""
        url.placeholderString = "http://localhost:1234/v1"
        url.delegate = self

        model.stringValue = BrainServer.model
        model.completes = true
        model.delegate = self
        reload.title = L("Обновить", "Reload")
        reload.bezelStyle = .rounded
        reload.controlSize = .small
        reload.target = self
        reload.action = #selector(reloadClicked)
        let modelRow = NSStackView(views: [model, reload])
        modelRow.spacing = 8

        status.font = .systemFont(ofSize: 11)
        status.textColor = .secondaryLabelColor
        status.stringValue = BrainServer.configured
            ? L("Текст (не звук) уходит на \(BrainServer.host), модель \(BrainServer.model).",
                "Text (not audio) goes to \(BrainServer.host), model \(BrainServer.model).")
            : L("Выбери сервис и вставь ключ, модель подберётся сама.", "Pick the service and paste the key; the model is chosen for you.")

        func label(_ s: String) -> NSTextField {
            let t = NSTextField(labelWithString: s)
            t.alignment = .right
            return t
        }
        grid = NSGridView(views: [
            [label(L("Сервис:", "Service:")), service],
            [label(L("Ключ API:", "API key:")), key],
            [NSGridCell.emptyContentView, keysLink],
            [label(L("Адрес:", "Address:")), url],
            [label(L("Модель:", "Model:")), modelRow],
            [NSGridCell.emptyContentView, status],
        ])
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 0).width = 150
        grid.rowAlignment = .firstBaseline
        grid.rowSpacing = 8
        grid.columnSpacing = 10
        grid.row(at: 2).topPadding = -4
        for v in [service, key, url, status] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            v.widthAnchor.constraint(equalToConstant: 320).isActive = true
        }
        model.translatesAutoresizingMaskIntoConstraints = false
        model.widthAnchor.constraint(equalToConstant: 320 - 8 - 80).isActive = true
        grid.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(grid)
        NSLayoutConstraint.activate([
            grid.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            grid.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            grid.topAnchor.constraint(equalTo: view.topAnchor),
            grid.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        updateService()
    }

    private func updateService() {
        let p = provider
        grid.row(at: 3).isHidden = !p.isCustom
        keysLink.title = p.isCustom ? L("Для своего сервера ключ обычно не нужен", "Your own server usually needs no key")
                                    : L("Где взять ключ \(p.name) →", "Get a \(p.name) key →")
        keysLink.isEnabled = !p.isCustom
    }

    @objc private func serviceChanged() {
        // A cloud key must never travel to an address typed for "own server" (and back).
        if provider.isCustom != (BrainProviders.all.first { $0.id == lastProviderId }?.isCustom ?? provider.isCustom) {
            key.stringValue = ""
        }
        lastProviderId = provider.id
        serial += 1
        reload.isEnabled = true
        updateService()
        model.removeAllItems()
        model.stringValue = ""
        status.stringValue = ""
        if !provider.isCustom, !key.stringValue.isEmpty { loadModels(pickDefault: true) }
    }

    @objc private func openKeys() {
        if let u = URL(string: provider.keysURL), !provider.keysURL.isEmpty { NSWorkspace.shared.open(u) }
    }

    @objc private func reloadClicked() { loadModels(pickDefault: model.stringValue.trimmingCharacters(in: .whitespaces).isEmpty) }

    /// A pasted key tells which service it is from; after a short pause the model list loads.
    func controlTextDidChange(_ obj: Notification) {
        guard (obj.object as? NSTextField) === key else { return }
        if let guess = BrainProviders.fromKey(key.stringValue), guess.id != provider.id,
           !(provider.isCustom && !url.stringValue.isEmpty) {
            service.selectItem(at: BrainProviders.all.firstIndex { $0.id == guess.id } ?? 0)
            lastProviderId = guess.id
            serial += 1
            updateService()
            model.removeAllItems()
            model.stringValue = ""
            status.stringValue = L("Похоже на ключ \(guess.name), выбрал его.", "Looks like a \(guess.name) key, selected it.")
        }
        pause?.invalidate()
        guard !key.stringValue.trimmingCharacters(in: .whitespaces).isEmpty else {
            serial += 1
            reload.isEnabled = true
            return
        }
        pause = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: false) { [weak self] _ in self?.loadModels(pickDefault: true) }
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard (obj.object as? NSTextField) === url, provider.isCustom, BrainServer.completionsURL(endpoint) != nil else { return }
        loadModels(pickDefault: model.stringValue.isEmpty)
    }

    func comboBoxSelectionDidChange(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in self?.saveAndProbe() }
    }

    private func loadModels(pickDefault: Bool) {
        guard BrainServer.completionsURL(endpoint) != nil else {
            status.stringValue = L("Впиши адрес сервера.", "Enter the server address.")
            return
        }
        serial += 1
        let mine = serial, p = provider
        status.stringValue = L("Проверяю ключ и загружаю модели…", "Checking the key and loading models…")
        reload.isEnabled = false
        BrainServer.fetchModels(base: endpoint, key: key.stringValue.trimmingCharacters(in: .whitespaces)) { [weak self] r in
            DispatchQueue.main.async {
                guard let self, mine == self.serial else { return }
                self.reload.isEnabled = true
                switch r {
                case .success(let all):
                    let ids = BrainProviders.chatModels(all)
                    let typed = self.model.stringValue.trimmingCharacters(in: .whitespaces)
                    self.model.removeAllItems()
                    self.model.addItems(withObjectValues: ids)
                    self.model.stringValue = pickDefault || typed.isEmpty ? (BrainProviders.pickDefault(p, ids) ?? "") : typed
                    self.saveAndProbe()
                case .failure(let e):
                    let code = (e as NSError).code
                    if code == 401 || code == 403 {
                        self.status.stringValue = L("\(p.name) не принял ключ. Проверь, что ключ от этого сервиса и скопирован целиком.",
                                                    "\(p.name) rejected the key. Check that it is for this service and copied in full.")
                    } else {
                        if !p.isCustom, self.model.stringValue.isEmpty { self.model.stringValue = p.preferredModels.first ?? "" }
                        self.status.stringValue = L("Список моделей не загрузился: \(e.localizedDescription)",
                                                    "Could not load the model list: \(e.localizedDescription)")
                    }
                }
            }
        }
    }

    /// Saves a usable set (address, model, key for a cloud service), then checks the model answers.
    private func saveAndProbe() {
        let m = model.stringValue.trimmingCharacters(in: .whitespaces)
        let k = key.stringValue.trimmingCharacters(in: .whitespaces)
        guard BrainServer.completionsURL(endpoint) != nil, !m.isEmpty, provider.isCustom || !k.isEmpty else { return }
        guard !BrainServer.insecureRemote(endpoint) else {
            status.stringValue = L("Для сервера в интернете нужен адрес https://. Обычный http работает только на этом маке и в домашней сети.",
                                   "A server on the internet needs an https:// address. Plain http works only on this Mac and your home network.")
            return
        }
        guard BrainServer.saveKey(k) else {
            status.stringValue = L("Не получилось сохранить ключ в Связку ключей. Попробуй ещё раз.", "Could not save the key to the Keychain. Try again.")
            return
        }
        BrainServer.baseURL = endpoint
        BrainServer.model = m
        serial += 1
        let mine = serial, host = BrainServer.host
        status.stringValue = L("Ключ подошёл, проверяю модель \(m)…", "The key works, checking model \(m)…")
        BrainServer.probe(base: endpoint, key: k, model: m) { [weak self] failure in
            DispatchQueue.main.async {
                guard let self, mine == self.serial else { return }
                self.status.stringValue = failure == nil
                    ? L("Всё работает, сохранено. Модель \(m), текст (не звук) уходит на \(host).",
                        "All set and saved. Model \(m); text (not audio) goes to \(host).")
                    : L("Ключ принят, но нейросеть не отвечает: \(failure!).", "The key is accepted, but the model does not answer: \(failure!).")
                self.saved()
            }
        }
    }
}
