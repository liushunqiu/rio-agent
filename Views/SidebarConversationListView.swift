import SwiftUI
import AppKit
import QuartzCore

struct SidebarConversationListView: NSViewRepresentable {
    let items: [ConversationSidebarItem]
    let selectedID: UUID?
    let isNavigationLocked: Bool
    let onSelect: (ConversationSidebarItem) -> Void
    let onDelete: (ConversationSidebarItem) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let tableView = SidebarConversationTableView()
        let column = NSTableColumn(identifier: SidebarConversationCellView.columnIdentifier)
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.rowHeight = SidebarConversationCellView.rowHeight
        tableView.intercellSpacing = NSSize(width: 0, height: 2)
        tableView.backgroundColor = .clear
        tableView.style = .plain
        tableView.rowSizeStyle = .custom
        tableView.gridStyleMask = []
        tableView.focusRingType = .none
        tableView.selectionHighlightStyle = .none
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.allowsEmptySelection = true
        tableView.allowsMultipleSelection = false
        tableView.dataSource = context.coordinator
        tableView.delegate = context.coordinator
        tableView.menuProvider = { [weak coordinator = context.coordinator] row in
            coordinator?.menu(for: row)
        }

        let scrollView = SidebarConversationScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.verticalScrollElasticity = .allowed
        scrollView.usesPredominantAxisScrolling = true
        scrollView.contentInsets = NSEdgeInsets(top: 8, left: 0, bottom: 4, right: 0)
        scrollView.documentView = tableView
        scrollView.sidebarTableView = tableView

        context.coordinator.tableView = tableView
        context.coordinator.configureLiveScrollObservation(scrollView)
        context.coordinator.update(parent: self, scrollView: scrollView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.update(parent: self, scrollView: scrollView)
    }

    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        private var parent: SidebarConversationListView
        private var items: [ConversationSidebarItem] = []
        private var itemIDs: [UUID] = []
        private var selectedID: UUID?
        private var isNavigationLocked = false
        private var isLiveScrolling = false
        private var deferredParent: SidebarConversationListView?
        weak var tableView: NSTableView?
        weak var scrollView: NSScrollView?

        init(parent: SidebarConversationListView) {
            self.parent = parent
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }

        func configureLiveScrollObservation(_ scrollView: NSScrollView) {
            guard self.scrollView !== scrollView else { return }
            if let oldScrollView = self.scrollView {
                NotificationCenter.default.removeObserver(self, name: NSScrollView.willStartLiveScrollNotification, object: oldScrollView)
                NotificationCenter.default.removeObserver(self, name: NSScrollView.didEndLiveScrollNotification, object: oldScrollView)
            }

            self.scrollView = scrollView
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(liveScrollStarted),
                name: NSScrollView.willStartLiveScrollNotification,
                object: scrollView
            )
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(liveScrollEnded),
                name: NSScrollView.didEndLiveScrollNotification,
                object: scrollView
            )
        }

        func update(parent: SidebarConversationListView, scrollView: NSScrollView) {
            guard let tableView else { return }

            if let column = tableView.tableColumns.first {
                let width = scrollView.contentView.bounds.width
                if abs(column.width - width) > 0.5 {
                    column.width = width
                }
            }

            let incomingIDs = parent.items.map(\.id)
            let idsChanged = itemIDs != incomingIDs
            if isLiveScrolling {
                deferredParent = parent
                self.parent = parent
                return
            }

            apply(parent: parent, incomingIDs: incomingIDs, idsChanged: idsChanged)
        }

        private func apply(parent: SidebarConversationListView, incomingIDs: [UUID], idsChanged: Bool) {
            guard let tableView else { return }

            let previousItems = items
            let previousSelectedID = selectedID
            let previousLockState = isNavigationLocked

            self.parent = parent
            items = parent.items
            itemIDs = incomingIDs
            selectedID = parent.selectedID
            isNavigationLocked = parent.isNavigationLocked

            if idsChanged {
                reloadDataPreservingScrollPosition(tableView)
                return
            }

            var rowsToReload = IndexSet()

            for index in items.indices where previousItems.indices.contains(index) {
                if items[index] != previousItems[index] {
                    rowsToReload.insert(index)
                }
            }

            if previousSelectedID != selectedID {
                if let previousSelectedID,
                   let previousIndex = items.firstIndex(where: { $0.id == previousSelectedID }) {
                    rowsToReload.insert(previousIndex)
                }
                if let selectedID,
                   let selectedIndex = items.firstIndex(where: { $0.id == selectedID }) {
                    rowsToReload.insert(selectedIndex)
                }
            }

            if previousLockState != isNavigationLocked {
                rowsToReload.formUnion(visibleRowIndexes(in: tableView))
            }

            rowsToReload = rowsToReload.intersection(visibleRowIndexes(in: tableView))
            guard !rowsToReload.isEmpty else { return }

            tableView.reloadData(
                forRowIndexes: rowsToReload,
                columnIndexes: IndexSet(integer: 0)
            )
        }

        private func visibleRowIndexes(in tableView: NSTableView) -> IndexSet {
            let visibleRange = tableView.rows(in: tableView.visibleRect)
            guard visibleRange.location != NSNotFound, visibleRange.length > 0 else {
                return IndexSet()
            }
            return IndexSet(integersIn: visibleRange.location..<(visibleRange.location + visibleRange.length))
        }

        private func reloadDataPreservingScrollPosition(_ tableView: NSTableView) {
            guard let scrollView = tableView.enclosingScrollView else {
                tableView.reloadData()
                return
            }

            let visibleOrigin = scrollView.contentView.bounds.origin
            tableView.reloadData()
            scrollView.contentView.scroll(to: visibleOrigin)
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }

        @objc private func liveScrollStarted() {
            isLiveScrolling = true
            deferredParent = nil
        }

        @objc private func liveScrollEnded() {
            isLiveScrolling = false
            guard let deferredParent else { return }
            self.deferredParent = nil
            let incomingIDs = deferredParent.items.map(\.id)
            let idsChanged = itemIDs != incomingIDs
            apply(parent: deferredParent, incomingIDs: incomingIDs, idsChanged: idsChanged)
        }

        func numberOfRows(in tableView: NSTableView) -> Int {
            items.count
        }

        func tableView(
            _ tableView: NSTableView,
            viewFor tableColumn: NSTableColumn?,
            row: Int
        ) -> NSView? {
            guard items.indices.contains(row) else { return nil }
            let identifier = SidebarConversationCellView.reuseIdentifier
            let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? SidebarConversationCellView
                ?? SidebarConversationCellView()
            cell.identifier = identifier
            let item = items[row]
            cell.configure(
                item: item,
                isSelected: selectedID == item.id,
                isDisabled: isNavigationLocked
            )
            return cell
        }

        func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
            guard !isNavigationLocked, items.indices.contains(row) else { return false }
            parent.onSelect(items[row])
            return false
        }

        func menu(for row: Int) -> NSMenu? {
            guard items.indices.contains(row) else { return nil }
            let item = items[row]
            let menu = NSMenu()
            let deleteItem = NSMenuItem(
                title: "删除",
                action: #selector(deleteConversation(_:)),
                keyEquivalent: ""
            )
            deleteItem.target = self
            deleteItem.representedObject = item.id
            deleteItem.isEnabled = !isNavigationLocked
            menu.addItem(deleteItem)
            return menu
        }

        @objc private func deleteConversation(_ sender: NSMenuItem) {
            guard !isNavigationLocked,
                  let id = sender.representedObject as? UUID,
                  let item = items.first(where: { $0.id == id }) else { return }
            parent.onDelete(item)
        }
    }
}

private final class SidebarConversationScrollView: NSScrollView {
    weak var sidebarTableView: SidebarConversationTableView?

    override func scrollWheel(with event: NSEvent) {
        adoptSidebarFirstResponder()
        super.scrollWheel(with: event)
    }

    private func adoptSidebarFirstResponder() {
        guard let window,
              let sidebarTableView,
              window.firstResponder !== sidebarTableView,
              sidebarTableView.acceptsFirstResponder else { return }
        window.makeFirstResponder(sidebarTableView)
    }
}

private final class SidebarConversationTableView: NSTableView {
    var menuProvider: ((Int) -> NSMenu?)?

    override var acceptsFirstResponder: Bool { true }

    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        return menuProvider?(row(at: point))
    }
}

private final class SidebarConversationCellView: NSTableCellView {
    static let columnIdentifier = NSUserInterfaceItemIdentifier("conversation")
    static let reuseIdentifier = NSUserInterfaceItemIdentifier("conversation-cell")
    static let rowHeight: CGFloat = 66

    private let cardView = FlippedView()
    private let textView = SidebarConversationTextDrawingView()
    private let titleField = NSTextField(labelWithString: "")
    private let directoryField = NSTextField(labelWithString: "")
    private var renderedSelectionState: Bool?
    private var renderedAlphaValue: CGFloat?
    private var renderedToolTip: String?

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    func configure(item: ConversationSidebarItem, isSelected: Bool, isDisabled: Bool) {
        alphaValue = isDisabled && !isSelected ? 0.58 : 1
        let targetAlpha = isDisabled && !isSelected ? 0.58 : 1
        if renderedAlphaValue != targetAlpha {
            renderedAlphaValue = targetAlpha
        }

        var needsTextRedraw = false
        if titleField.stringValue != item.title {
            titleField.stringValue = item.title
            needsTextRedraw = true
        }

        if renderedSelectionState != isSelected {
            titleField.font = .systemFont(ofSize: 13, weight: isSelected ? .semibold : .regular)
            titleField.textColor = isSelected ? AppKitSidebarColors.textPrimary : AppKitSidebarColors.textSecondary
            configureCard(isSelected: isSelected)
            renderedSelectionState = isSelected
            needsTextRedraw = true
        }

        if directoryField.stringValue != item.workingDirectoryLabel {
            directoryField.stringValue = item.workingDirectoryLabel
            needsTextRedraw = true
        }
        let directoryColor = item.workingDirectory == nil
            ? AppKitSidebarColors.textTertiary.withAlphaComponent(0.72)
            : AppKitSidebarColors.textTertiary
        if directoryField.textColor != directoryColor {
            directoryField.textColor = directoryColor
            needsTextRedraw = true
        }

        toolTip = [item.title, item.workingDirectoryLabel].joined(separator: "\n")
        let toolTipText = [item.title, item.workingDirectoryLabel].joined(separator: "\n")
        if renderedToolTip != toolTipText {
            renderedToolTip = toolTipText
        }

        if needsTextRedraw {
            textView.needsDisplay = true
        }
    }

    private func setupView() {
        wantsLayer = true
        layer?.masksToBounds = false

        cardView.wantsLayer = true
        cardView.layer?.cornerRadius = 8
        cardView.layer?.masksToBounds = true
        addSubview(cardView)

        textView.configure(titleField: titleField, directoryField: directoryField)
        cardView.addSubview(textView)

        configureTextField(titleField, font: .systemFont(ofSize: 13), color: AppKitSidebarColors.textSecondary)
        titleField.lineBreakMode = .byTruncatingMiddle

        configureTextField(directoryField, font: .systemFont(ofSize: 11), color: AppKitSidebarColors.textTertiary)
        directoryField.lineBreakMode = .byTruncatingMiddle
    }

    override func layout() {
        super.layout()

        cardView.frame = bounds.insetBy(dx: 8, dy: 2)
        textView.frame = cardView.bounds
        let textWidth = max(0, cardView.bounds.width - 24)
        titleField.frame = NSRect(x: 12, y: 10, width: textWidth, height: 19)
        directoryField.frame = NSRect(x: 12, y: 36, width: textWidth, height: 17)
    }

    private func configureTextField(_ field: NSTextField, font: NSFont, color: NSColor) {
        field.autoresizingMask = []
        field.font = font
        field.textColor = color
        field.backgroundColor = .clear
        field.isBordered = false
        field.isEditable = false
        field.isSelectable = false
        field.drawsBackground = false
        field.cell?.wraps = false
        field.cell?.isScrollable = false
        field.lineBreakMode = .byTruncatingTail
    }

    private func configureCard(isSelected: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        cardView.layer?.backgroundColor = isSelected ? AppKitSidebarColors.glass.cgColor : NSColor.clear.cgColor
        cardView.layer?.borderWidth = isSelected ? 1 : 0
        cardView.layer?.borderColor = isSelected ? AppKitSidebarColors.accent.withAlphaComponent(0.30).cgColor : NSColor.clear.cgColor
        CATransaction.commit()
    }
}

private final class SidebarConversationTextDrawingView: NSView {
    private weak var titleField: NSTextField?
    private weak var directoryField: NSTextField?

    override var isFlipped: Bool { true }

    func configure(titleField: NSTextField, directoryField: NSTextField) {
        self.titleField = titleField
        self.directoryField = directoryField
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard let titleField,
              let directoryField else { return }

        titleField.cell?.draw(withFrame: titleField.frame, in: self)
        directoryField.cell?.draw(withFrame: directoryField.frame, in: self)
    }
}

private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

private enum AppKitSidebarColors {
    static let glass = NSColor.white.withAlphaComponent(0.045)
    static let accent = NSColor(calibratedRed: 0.24, green: 0.78, blue: 0.62, alpha: 1)
    static let textPrimary = NSColor(calibratedRed: 0.94, green: 0.96, blue: 0.98, alpha: 1)
    static let textSecondary = NSColor(calibratedRed: 0.62, green: 0.67, blue: 0.72, alpha: 1)
    static let textTertiary = NSColor(calibratedRed: 0.42, green: 0.48, blue: 0.54, alpha: 1)
}
