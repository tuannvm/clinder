import AppKit

final class DynamicBackgroundView: NSView {
    var fillColor: NSColor = .windowBackgroundColor {
        didSet { updateLayerColors() }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateLayerColors()
    }

    private func setup() {
        wantsLayer = true
        updateLayerColors()
    }

    private func updateLayerColors() {
        layer?.backgroundColor = resolvedCGColor(fillColor, for: effectiveAppearance)
    }
}

final class SidebarButton: NSButton {
    var isSidebarSelected = false {
        didSet { updateStyle() }
    }

    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateLayerColors()
    }

    func configure(title: String, symbol: String) {
        setAccessibilityLabel(title)
        toolTip = title
        titleLabel.stringValue = title
        iconView.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
    }

    private func setup() {
        title = ""
        image = nil
        isBordered = false
        alignment = .left
        focusRingType = .none
        wantsLayer = true
        layer?.cornerRadius = 7

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.imageScaling = .scaleProportionallyDown
        iconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.lineBreakMode = .byTruncatingTail

        addSubview(iconView)
        addSubview(titleLabel)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 16),
            iconView.heightAnchor.constraint(equalToConstant: 16),
            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 7),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])

        updateStyle()
    }

    private func updateStyle() {
        updateLayerColors()
        titleLabel.font = .systemFont(ofSize: 13, weight: isSidebarSelected ? .semibold : .regular)
        titleLabel.textColor = .labelColor
        iconView.contentTintColor = .labelColor
    }

    private func updateLayerColors() {
        layer?.backgroundColor = isSidebarSelected
            ? resolvedCGColor(.quaternaryLabelColor.withAlphaComponent(0.22), for: effectiveAppearance)
            : NSColor.clear.cgColor
    }
}

func resolvedCGColor(_ color: NSColor, for appearance: NSAppearance) -> CGColor {
    var resolvedColor = color.cgColor
    appearance.performAsCurrentDrawingAppearance {
        resolvedColor = color.cgColor
    }
    return resolvedColor
}
