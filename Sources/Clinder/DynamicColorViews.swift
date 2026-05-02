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
        layer?.cornerRadius = 7
        updateLayerColors()
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
