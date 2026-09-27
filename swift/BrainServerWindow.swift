// The Brain in the cloud: a small settings window in the macOS style (labels on
// the left, controls on the right, Cancel and Save at the bottom right).
// People usually have a key and the name of a service, not an API address:
// the service is picked or guessed from the key, the model list loads by itself
// and a sensible model is chosen. Saving switches the Brain to the server.

import AppKit

final class BrainServerWindow: NSObject, NSWindowDelegate, NSTextFieldDelegate {
    private let window: NSWindow
    private let service = NSPopUpButton()
    private let key = NSSecureTextField()
    private let keysLink = NSButton()
    private let urlLabel = NSTextField(labelWithString: "")
    private let url = NSTextField()
    private let model = NSComboBox()
    private let reload = NSButton()
    private let status = NSTextField(wrappingLabelWithString: "")
    private let save = NSButton()
    private var grid: NSGridView!
    private var pause: Timer?
    private var loadSerial = 0
    private var saved = false

    private var provider: BrainProvider { BrainProviders.all[max(0, service.indexOfSelectedItem)] }
    private var endpoint: String { provider.isCustom ? url.stringValue.trimmingCharacters(in: .whitespaces) : provider.baseURL }

    override init() {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 300),
                          styleMask: [.titled, .closable], backing: .buffered, defer: false)
        super.init()
        window.title = L("Мозг в облаке", "Brain in the Cloud")
        window.isReleasedWhenClosed = false
        window.delegate = self
        build()
    }

    /// Shows the window modally; true when the user saved.
    func run() -> Bool {
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(key.stringValue.isEmpty ? key : model)
        if !key.stringValue.isEmpty, !provider.isCustom {
            onMainInModal { [weak self] in self?.loadModels(pickDefault: self?.model.stringValue.isEmpty ?? true) }
        }
        NSApp.runModal(for: window)
        window.orderOut(nil)
        pause?.invalidate()
        return saved
    }

    // MARK: layout

    private func build() {
        let intro = NSTextField(wrappingLabelWithString: L(
            "Выбери сервис и вставь ключ, модель подберётся сама. Распознавание остаётся на маке, звук никуда не уходит, на сервер отправляется только готовый текст.",
            "Pick the service and paste the key; the model is chosen for you. Recognition stays on this Mac and audio never leaves it; only the recognized text is sent."))
        intro.font = .systemFont(ofSize: 12)
        intro.textColor = .secondaryLabelColor

        for p in BrainProviders.all { service.addItem(withTitle: BrainProviders.title(p)) }
        let savedProvider = BrainServer.baseURL.isEmpty ? BrainProviders.deepseek : BrainProviders.fromURL(BrainServer.baseURL)
        service.selectItem(at: BrainProviders.all.firstIndex { $0.id == savedProvider.id } ?? 0)
        service.target = self
        service.action = #selector(serviceChanged)

        key.stringValue = BrainServer.apiKey
        key.placeholderString = L("вставь ключ", "paste the key")
        key.delegate = self
        key.toolTip = L("Хранится в Связке ключей", "Kept in the Keychain")

        keysLink.bezelStyle = .inline
        keysLink.isBordered = false
        keysLink.contentTintColor = .linkColor
        keysLink.font = .systemFont(ofSize: 11)
        keysLink.target = self
        keysLink.action = #selector(openKeys)

        url.stringValue = savedProvider.isCustom ? BrainServer.baseURL : ""
        url.placeholderString = "http://localhost:1234/v1"
        url.delegate = self
        url.toolTip = L("LM Studio: http://localhost:1234/v1, Ollama: http://localhost:11434/v1", "LM Studio: http://localhost:1234/v1, Ollama: http://localhost:11434/v1")

        model.stringValue = BrainServer.model
        model.completes = true
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
            ? L("Текст (не звук) уходит на \(BrainServer.host), модель \(BrainServer.model).", "Text (not audio) goes to \(BrainServer.host), model \(BrainServer.model).")
            : ""

        func rowLabel(_ s: String) -> NSTextField {
            let t = NSTextField(labelWithString: s)
            t.alignment = .right
            return t
        }
        urlLabel.stringValue = L("Адрес:", "Address:")
        urlLabel.alignment = .right

        grid = NSGridView(views: [
            [rowLabel(L("Сервис:", "Service:")), service],
            [rowLabel(L("Ключ API:", "API Key:")), key],
            [NSGridCell.emptyContentView, keysLink],
            [urlLabel, url],
            [rowLabel(L("Модель:", "Model:")), modelRow],
            [NSGridCell.emptyContentView, status],
        ])
        grid.rowSpacing = 8
        grid.columnSpacing = 10
        grid.column(at: 0).xPlacement = .trailing
        grid.rowAlignment = .firstBaseline
        grid.row(at: 2).topPadding = -4
        grid.row(at: 5).topPadding = -2
        for v in [service, key, url, status] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            v.widthAnchor.constraint(equalToConstant: 330).isActive = true
        }
        model.translatesAutoresizingMaskIntoConstraints = false
        model.widthAnchor.constraint(equalToConstant: 330 - 8 - 80).isActive = true

        let cancel = NSButton(title: L("Отмена", "Cancel"), target: self, action: #selector(cancelClicked))
        cancel.keyEquivalent = "\u{1b}"
        save.title = L("Сохранить", "Save")
        save.bezelStyle = .rounded
        save.keyEquivalent = "\r"
        save.target = self
        save.action = #selector(saveClicked)
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let buttons = NSStackView(views: [spacer, cancel, save])
        buttons.spacing = 10

        let root = NSStackView(views: [intro, grid, buttons])
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 16
        root.edgeInsets = NSEdgeInsets(top: 18, left: 20, bottom: 18, right: 20)
        root.setCustomSpacing(20, after: grid)
        intro.translatesAutoresizingMaskIntoConstraints = false
        intro.widthAnchor.constraint(equalToConstant: 460).isActive = true
        buttons.translatesAutoresizingMaskIntoConstraints = false
        root.translatesAutoresizingMaskIntoConstraints = false

        let content = NSView()
        content.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            root.topAnchor.constraint(equalTo: content.topAnchor),
            root.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            buttons.widthAnchor.constraint(equalToConstant: 460),
        ])
        window.contentView = content
        updateService()
    }

    private func updateService() {
        let p = provider
        grid.row(at: 3).isHidden = !p.isCustom   // the address row exists only for "own server"
        keysLink.title = p.isCustom ? L("Для своего сервера ключ обычно не нужен", "Your own server usually needs no key")
                                    : L("Где взять ключ \(p.name) →", "Get a \(p.name) key →")
        keysLink.isEnabled = !p.isCustom
    }

    // MARK: actions

    @objc private func serviceChanged() {
        updateService()
        model.removeAllItems()
        model.stringValue = ""
        status.stringValue = ""
        if !provider.isCustom, !key.stringValue.isEmpty { loadModels(pickDefault: true) }
    }

    @objc private func openKeys() {
        if let u = URL(string: provider.keysURL), !provider.keysURL.isEmpty { NSWorkspace.shared.open(u) }
    }

    @objc private func reloadClicked() {
        loadModels(pickDefault: model.stringValue.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    /// A pasted key tells which service it is from; after a short pause the model list loads.
    func controlTextDidChange(_ obj: Notification) {
        guard (obj.object as? NSTextField) === key else { return }
        if let guess = BrainProviders.fromKey(key.stringValue), guess.id != provider.id,
           !(provider.isCustom && !url.stringValue.isEmpty) {
            service.selectItem(at: BrainProviders.all.firstIndex { $0.id == guess.id } ?? 0)
            updateService()
            model.removeAllItems()
            model.stringValue = ""
            status.stringValue = L("Похоже на ключ \(guess.name), выбрал его.", "Looks like a \(guess.name) key, selected it.")
        }
        pause?.invalidate()
        guard !key.stringValue.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        let t = Timer(timeInterval: 0.6, repeats: false) { [weak self] _ in self?.loadModels(pickDefault: true) }
        RunLoop.main.add(t, forMode: .modalPanel)
        RunLoop.main.add(t, forMode: .default)
        pause = t
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard (obj.object as? NSTextField) === url, provider.isCustom, BrainServer.completionsURL(endpoint) != nil else { return }
        loadModels(pickDefault: model.stringValue.isEmpty)
    }

    private func loadModels(pickDefault: Bool) {
        guard BrainServer.completionsURL(endpoint) != nil else {
            status.stringValue = L("Впиши адрес сервера.", "Enter the server address.")
            return
        }
        loadSerial += 1
        let mine = loadSerial, p = provider
        status.stringValue = L("Проверяю ключ и загружаю модели…", "Checking the key and loading models…")
        reload.isEnabled = false
        BrainServer.fetchModels(base: endpoint, key: key.stringValue.trimmingCharacters(in: .whitespaces)) { [weak self] r in
            onMainInModal {
                guard let self, mine == self.loadSerial else { return }
                self.reload.isEnabled = true
                switch r {
                case .success(let all):
                    let ids = BrainProviders.chatModels(all)
                    let typed = self.model.stringValue.trimmingCharacters(in: .whitespaces)
                    self.model.removeAllItems()
                    self.model.addItems(withObjectValues: ids)
                    self.model.stringValue = pickDefault || typed.isEmpty ? (BrainProviders.pickDefault(p, ids) ?? "") : typed
                    self.status.stringValue = L("Ключ подошёл. Выбрана модель \(self.model.stringValue), можно сохранять.",
                                                "The key works. Model \(self.model.stringValue) selected, ready to save.")
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

    @objc private func cancelClicked() { NSApp.stopModal() }
    func windowWillClose(_ notification: Notification) { if NSApp.modalWindow === window { NSApp.stopModal() } }

    @objc private func saveClicked() {
        let m = model.stringValue.trimmingCharacters(in: .whitespaces)
        let k = key.stringValue.trimmingCharacters(in: .whitespaces)
        guard BrainServer.completionsURL(endpoint) != nil else {
            status.stringValue = L("Впиши адрес сервера вида https://… или http://…", "Enter a server address like https://… or http://…")
            return
        }
        guard provider.isCustom || !k.isEmpty else {
            status.stringValue = L("Вставь ключ.", "Paste the key.")
            window.makeFirstResponder(key)
            return
        }
        guard !m.isEmpty else {
            status.stringValue = L("Выбери модель или нажми «Обновить».", "Pick a model or press Reload.")
            return
        }
        if BrainServer.insecureRemote(endpoint) {
            let warn = NSAlert()
            warn.messageText = L("Адрес без шифрования", "Unencrypted Address")
            warn.informativeText = L("Адрес начинается с http://, а сервер не на этом маке и не в домашней сети. Текст и ключ пойдут по интернету открыто. Лучше https://. Всё равно сохранить?",
                                     "The address starts with http:// and the server is neither on this Mac nor on your home network. Text and key will cross the internet in the clear. Prefer https://. Save anyway?")
            warn.addButton(withTitle: L("Сохранить", "Save"))
            warn.addButton(withTitle: L("Исправить", "Edit"))
            guard warn.runModal() == .alertFirstButtonReturn else { return }
        }
        BrainServer.baseURL = endpoint
        BrainServer.apiKey = k
        BrainServer.model = m
        saved = true
        NSApp.stopModal()
    }
}
