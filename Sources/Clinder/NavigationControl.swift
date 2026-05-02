import AppKit

@MainActor
final class NavigationControl: NSView {
    var onBack: (() -> Void)?
    var onForward: (() -> Void)?

    var canGoBack = false {
        didSet {
            backButton.isEnabled = canGoBack
            updateTint()
        }
    }

    var canGoForward = false {
        didSet {
            forwardButton.isEnabled = canGoForward
            updateTint()
        }
    }

    private let backButton = NSButton()
    private let forwardButton = NSButton()
    private let divider = NSView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        wantsLayer = true
        layer?.cornerRadius = 13
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.35).cgColor
        layer?.borderWidth = 1

        configure(button: backButton, symbol: "chevron.left", action: #selector(backClicked(_:)))
        configure(button: forwardButton, symbol: "chevron.right", action: #selector(forwardClicked(_:)))

        divider.translatesAutoresizingMaskIntoConstraints = false
        divider.wantsLayer = true
        divider.layer?.backgroundColor = NSColor.separatorColor.withAlphaComponent(0.45).cgColor

        addSubview(backButton)
        addSubview(forwardButton)
        addSubview(divider)

        NSLayoutConstraint.activate([
            backButton.leadingAnchor.constraint(equalTo: leadingAnchor),
            backButton.topAnchor.constraint(equalTo: topAnchor),
            backButton.bottomAnchor.constraint(equalTo: bottomAnchor),
            backButton.widthAnchor.constraint(equalTo: widthAnchor, multiplier: 0.5),
            forwardButton.trailingAnchor.constraint(equalTo: trailingAnchor),
            forwardButton.topAnchor.constraint(equalTo: topAnchor),
            forwardButton.bottomAnchor.constraint(equalTo: bottomAnchor),
            forwardButton.widthAnchor.constraint(equalTo: widthAnchor, multiplier: 0.5),
            divider.centerXAnchor.constraint(equalTo: centerXAnchor),
            divider.centerYAnchor.constraint(equalTo: centerYAnchor),
            divider.widthAnchor.constraint(equalToConstant: 1),
            divider.heightAnchor.constraint(equalToConstant: 16)
        ])

        updateTint()
    }

    private func configure(button: NSButton, symbol: String, action: Selector) {
        button.translatesAutoresizingMaskIntoConstraints = false
        button.title = ""
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleNone
        button.isBordered = false
        button.bezelStyle = .regularSquare
        button.target = self
        button.action = action
        button.focusRingType = .none
    }

    private func updateTint() {
        backButton.contentTintColor = canGoBack ? .labelColor : .tertiaryLabelColor
        forwardButton.contentTintColor = canGoForward ? .labelColor : .tertiaryLabelColor
    }

    @objc private func backClicked(_ sender: NSButton) {
        guard canGoBack else { return }
        onBack?()
    }

    @objc private func forwardClicked(_ sender: NSButton) {
        guard canGoForward else { return }
        onForward?()
    }
}
