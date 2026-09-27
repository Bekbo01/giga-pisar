// «Что нового»: короткий список изменений, который показывается в окне
// проверки обновлений. Про текущую версию текст зашит здесь (работает без
// сети), про свежую приезжает в манифесте update.json полем notes:
//   "notes": { "ru": ["…", "…"], "en": ["…", "…"] }
// Правило: две-четыре строки, каждая в одно предложение, без точек в конце.

import AppKit

/// Что изменилось в ЭТОЙ версии. Обновлять при каждом выпуске вместе с номером.
let WHATS_NEW: [String] = uiIsRussian ? [
    "Мозг на своём сервере или в облаке по ключу: OpenRouter, DeepSeek, OpenAI, свой LM Studio. Работает и на маках с Intel",
    "Ключ хранится в Связке ключей, на сервер уходит только текст, звук остаётся на маке",
    "Правка выделенного теперь отдельным пунктом в меню: видно, что это, и можно выключить",
    "Новая галочка в меню Мозга: править каждую диктовку без команды",
] : [
    "The Brain can think on your own server or a cloud model with a key: OpenRouter, DeepSeek, OpenAI, your LM Studio. Works on Intel Macs too",
    "The key is kept in the Keychain; only text goes to the server, audio stays on the Mac",
    "Editing a selection by voice has its own menu item: clear what it is, and it can be turned off",
    "New Brain menu option: edit every take without a command",
]

/// Разбор поля notes из манифеста: словарь по языкам, список или строка.
func parseNotes(_ raw: Any?) -> [String] {
    var v = raw
    if let dict = raw as? [String: Any] {
        v = dict[uiIsRussian ? "ru" : "en"] ?? dict["ru"] ?? dict["en"]
    }
    if let list = v as? [String] { return list.filter { !$0.isEmpty } }
    if let s = v as? String {
        return s.split(whereSeparator: { $0 == "\n" }).map { String($0) }.filter { !$0.isEmpty }
    }
    return []
}

/// Плашка «Что нового в X» для NSAlert.accessoryView: мягкая подложка со
/// скруглением, заголовок мелким полужирным, пункты с висячим маркером.
func whatsNewView(version: String, notes: [String]) -> NSView? {
    bulletsView(header: L("Что нового в \(version)", "What's new in \(version)"), lines: notes)
}

/// Та же плашка с любым заголовком и любыми пунктами (инструкция к Мозгу).
func bulletsView(header headerText: String, lines notes: [String], width: CGFloat = 300) -> NSView? {
    guard !notes.isEmpty else { return nil }
    let pad: CGFloat = 12

    let stack = NSStackView()
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 5
    stack.translatesAutoresizingMaskIntoConstraints = false

    let head = NSTextField(labelWithString: headerText)
    head.font = .systemFont(ofSize: 11, weight: .semibold)
    head.textColor = .secondaryLabelColor
    stack.addArrangedSubview(head)
    stack.setCustomSpacing(7, after: head)

    let textWidth = width - pad * 2 - 14
    for line in notes {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .firstBaseline
        row.spacing = 0
        let dot = NSTextField(labelWithString: "•")
        dot.font = .systemFont(ofSize: 12)
        dot.textColor = .secondaryLabelColor
        dot.translatesAutoresizingMaskIntoConstraints = false
        dot.widthAnchor.constraint(equalToConstant: 14).isActive = true
        let text = NSTextField(wrappingLabelWithString: line)
        text.font = .systemFont(ofSize: 12)
        text.textColor = .labelColor
        text.isSelectable = false
        text.preferredMaxLayoutWidth = textWidth
        text.translatesAutoresizingMaskIntoConstraints = false
        text.widthAnchor.constraint(equalToConstant: textWidth).isActive = true
        row.addArrangedSubview(dot)
        row.addArrangedSubview(text)
        stack.addArrangedSubview(row)
    }

    let box = NSBox()
    box.boxType = .custom
    box.cornerRadius = 8
    box.borderWidth = 0
    box.fillColor = NSColor.labelColor.withAlphaComponent(0.06)
    box.contentViewMargins = .zero
    box.translatesAutoresizingMaskIntoConstraints = false
    box.contentView?.addSubview(stack)
    guard let content = box.contentView else { return nil }
    NSLayoutConstraint.activate([
        stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: pad),
        stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -pad),
        stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 10),
        stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -11),
        box.widthAnchor.constraint(equalToConstant: width),
    ])
    box.layoutSubtreeIfNeeded()
    box.frame = NSRect(origin: .zero, size: box.fittingSize)
    return box
}
