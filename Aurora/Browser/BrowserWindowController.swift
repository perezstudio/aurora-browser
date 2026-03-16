import AppKit
import SwiftUI
import SwiftData

// MARK: - Window Controller

final class BrowserWindowController: NSWindowController {

    let splitViewController: BrowserSplitViewController

    init(browserState: BrowserState, modelContainer: ModelContainer) {
        let splitVC = BrowserSplitViewController(browserState: browserState, modelContainer: modelContainer)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.backgroundColor = .windowBackgroundColor
        window.minSize = NSSize(width: 800, height: 500)
        window.setFrameAutosaveName("AuroraMainWindow")
        window.titlebarSeparatorStyle = .none

        // Hide the titlebar so content is truly edge-to-edge.
        // Traffic lights (close/minimize/zoom) float over the content.
        if let titlebarView = window.standardWindowButton(.closeButton)?.superview {
            titlebarView.wantsLayer = true
            titlebarView.layer?.backgroundColor = .clear
        }
        window.toolbar = nil
        window.center()

        self.splitViewController = splitVC
        super.init(window: window)

        // Add split view as subview (not contentViewController) to avoid
        // Auto Layout-driven window resizing when internal constraints change
        guard let contentView = window.contentView else { return }
        splitVC.view.frame = contentView.bounds
        splitVC.view.autoresizingMask = [.width, .height]
        contentView.addSubview(splitVC.view)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

// MARK: - Split View Controller

final class BrowserSplitViewController: NSSplitViewController {

    private let browserState: BrowserState
    private let modelContainer: ModelContainer

    init(browserState: BrowserState, modelContainer: ModelContainer) {
        self.browserState = browserState
        self.modelContainer = modelContainer
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        splitView.dividerStyle = .thin

        // --- Sidebar pane ---
        // Use standard viewController init (NOT sidebarWithViewController) to avoid
        // automatic liquid glass vibrancy and titlebar space reservation.
        let sidebarContent = SidebarView()
            .environment(browserState)
            .modelContainer(modelContainer)
        let sidebarHosting = NSHostingController(rootView: sidebarContent)
        sidebarHosting.view.wantsLayer = true
        sidebarHosting.view.layer?.backgroundColor = .clear
        let sidebarItem = NSSplitViewItem(viewController: sidebarHosting)
        sidebarItem.canCollapse = true
        sidebarItem.minimumThickness = 200
        sidebarItem.maximumThickness = 360
        sidebarItem.holdingPriority = .defaultLow + 1
        addSplitViewItem(sidebarItem)

        // --- Content pane ---
        let contentPaneContent = ContentPaneView()
            .environment(browserState)
            .modelContainer(modelContainer)
        let contentHosting = NSHostingController(rootView: contentPaneContent)
        contentHosting.view.wantsLayer = true
        contentHosting.view.layer?.backgroundColor = .clear
        let contentItem = NSSplitViewItem(viewController: contentHosting)
        contentItem.canCollapse = false
        contentItem.minimumThickness = 400
        addSplitViewItem(contentItem)
    }

    func toggleSidebarPane() {
        guard splitViewItems.count > 0 else { return }
        let item = splitViewItems[0]
        item.animator().isCollapsed.toggle()
    }
}
