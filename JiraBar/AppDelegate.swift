import Cocoa
import SwiftUI
import Foundation
import Defaults

private final class IssueMenuRowView: NSView {
    private let checkbox: NSButton
    private let titleButton: NSButton
    private let detailsLabel: NSTextField
    private let moreButton: NSButton
    
    override var intrinsicContentSize: NSSize {
        NSSize(width: 360, height: 52)
    }
    
    var onAcknowledgeToggle: ((Bool) -> Void)?
    var onOpen: (() -> Void)?
    var onShowActions: (() -> Void)?
    
    init(issue: Issue, isAcknowledged: Bool) {
        checkbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
        titleButton = NSButton(title: issue.fields.summary.trunc(length: 50), target: nil, action: nil)
        detailsLabel = NSTextField(labelWithString: "\(issue.key)   \(issue.fields.assignee?.displayName ?? "Unassign")   \(issue.fields.issuetype.name)")
        moreButton = NSButton(title: "⋯", target: nil, action: nil)
        super.init(frame: .zero)
        setup(issue: issue, isAcknowledged: isAcknowledged)
    }
    
    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setup(issue: Issue, isAcknowledged: Bool) {
        frame = NSRect(x: 0, y: 0, width: 360, height: 52)
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.backgroundColor = NSColor.systemOrange.withAlphaComponent(0.12).cgColor
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.systemOrange.withAlphaComponent(0.35).cgColor
        
        checkbox.state = isAcknowledged ? .on : .off
        checkbox.setButtonType(.switch)
        checkbox.target = self
        checkbox.action = #selector(toggleAcknowledged)
        checkbox.translatesAutoresizingMaskIntoConstraints = false
        
        titleButton.isBordered = false
        titleButton.alignment = .left
        titleButton.font = NSFont.boldSystemFont(ofSize: NSFont.systemFontSize)
        titleButton.contentTintColor = .labelColor
        titleButton.target = self
        titleButton.action = #selector(openIssue)
        titleButton.translatesAutoresizingMaskIntoConstraints = false
        
        detailsLabel.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        detailsLabel.textColor = .secondaryLabelColor
        detailsLabel.lineBreakMode = .byTruncatingTail
        detailsLabel.translatesAutoresizingMaskIntoConstraints = false
        
        moreButton.bezelStyle = .texturedRounded
        moreButton.target = self
        moreButton.action = #selector(showActions)
        moreButton.translatesAutoresizingMaskIntoConstraints = false
        
        addSubview(checkbox)
        addSubview(titleButton)
        addSubview(detailsLabel)
        addSubview(moreButton)
        
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 360),
            checkbox.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            checkbox.centerYAnchor.constraint(equalTo: centerYAnchor),
            
            moreButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            moreButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            moreButton.widthAnchor.constraint(equalToConstant: 28),
            
            titleButton.leadingAnchor.constraint(equalTo: checkbox.trailingAnchor, constant: 8),
            titleButton.trailingAnchor.constraint(lessThanOrEqualTo: moreButton.leadingAnchor, constant: -8),
            titleButton.topAnchor.constraint(equalTo: topAnchor, constant: 7),
            
            detailsLabel.leadingAnchor.constraint(equalTo: titleButton.leadingAnchor),
            detailsLabel.trailingAnchor.constraint(equalTo: moreButton.leadingAnchor, constant: -8),
            detailsLabel.topAnchor.constraint(equalTo: titleButton.bottomAnchor, constant: 2),
            detailsLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -7)
        ])
    }
    
    @objc
    private func toggleAcknowledged() {
        onAcknowledgeToggle?(checkbox.state == .on)
    }
    
    @objc
    private func openIssue() {
        onOpen?()
    }
    
    @objc
    private func showActions() {
        onShowActions?()
    }
}

@main
class AppDelegate: NSObject, NSApplicationDelegate {

    @Default(.refreshRate) var refreshRate
    @Default(.jql) var jql
    @Default(.orgName) var orgName
    @Default(.instanceType) var instanceType
    @Default(.jiraHost) var jiraHost
    @Default(.knownIssueKeys) var knownIssueKeys
    @Default(.pendingNewIssueKeys) var pendingNewIssueKeys

    let jiraClient = JiraClient()

    /// Base web URL for opening pages in the browser — mirrors JiraClient.baseUrl.
    private var baseUrl: String {
        switch instanceType {
        case .cloud:  return "https://\(orgName).atlassian.net"
        case .server: return jiraHost.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }
    }
    
    var statusBarItem: NSStatusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    let menu: NSMenu = NSMenu()

    var timer: Timer? = nil
    
    var preferencesWindow: NSWindow!
    var aboutWindow: NSWindow!
    
    var unknownPersonAvatar: NSImage!
    private let normalIcon: NSImage? = {
        let icon = NSImage(named: "mark-gradient-white-jira")
        icon?.size = NSSize(width: 18, height: 18)
        icon?.isTemplate = true
        return icon
    }()
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        NotificationCenter.default.addObserver(self, selector: #selector(AppDelegate.windowClosed), name: NSWindow.willCloseNotification, object: nil)
        guard let statusButton = statusBarItem.button else { return }
        statusButton.image = normalIcon
        statusButton.imagePosition = .imageLeft
        
        statusBarItem.menu = menu
        
        timer = Timer.scheduledTimer(
            timeInterval: Double(refreshRate * 60),
            target: self,
            selector: #selector(refreshMenu),
            userInfo: nil,
            repeats: true
        )
        timer?.fire()
        RunLoop.main.add(timer!, forMode: .common)
        
        NSApp.setActivationPolicy(.accessory)
        
        let config = NSImage.SymbolConfiguration(pointSize: 24, weight: .regular)
        unknownPersonAvatar = NSImage(systemSymbolName: "person.crop.circle.badge.questionmark", accessibilityDescription: nil)!.withSymbolConfiguration(config)!
        // Disabled for local/fork builds; upstream release checks are noisy here.
    }

    func applicationWillTerminate(_ aNotification: Notification) {}

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }
}

extension AppDelegate {
    @objc
    func refreshMenu() {
        NSLog("Refreshing menu")
        menu.removeAllItems()
        
        jiraClient.getIssuesByJql() { resp in
            let issues = resp.issues ?? []
            let currentIssueKeys = Set(issues.map(\.key))
            let previousKnownIssueKeys = Set(self.knownIssueKeys)
            var pendingNewIssueKeys = Set(self.pendingNewIssueKeys).intersection(currentIssueKeys)
            let newlyDetectedIssueKeys = currentIssueKeys.subtracting(previousKnownIssueKeys)
            pendingNewIssueKeys.formUnion(newlyDetectedIssueKeys)
            
            self.knownIssueKeys = Array(currentIssueKeys).sorted()
            self.pendingNewIssueKeys = Array(pendingNewIssueKeys).sorted()
            self.updateStatusBarAppearance(hasUnacknowledgedNewIssues: !pendingNewIssueKeys.isEmpty)
            self.statusBarItem.button?.title = String(issues.count)
            
            if !newlyDetectedIssueKeys.isEmpty {
                let newIssues = issues.filter { newlyDetectedIssueKeys.contains($0.key) }
                self.notifyAboutNewIssues(newIssues)
            }
            
            let statusOrder: [String] = [
                "Open",
                "Selected for Development",
                "On Hold",
                "Ready for QA",
                "In Review"
            ]
            let statusRank = Dictionary(uniqueKeysWithValues: statusOrder.enumerated().map { ($0.element, $0.offset) })
            let issuesByStatus = Dictionary(grouping: issues) { $0.fields.status.name }
                .sorted { lhs, rhs in
                    let lhsRank = statusRank[lhs.key] ?? Int.max
                    let rhsRank = statusRank[rhs.key] ?? Int.max
                    if lhsRank != rhsRank { return lhsRank < rhsRank }
                    return lhs.key < rhs.key
                }
            
            for (status, unsortedStatusIssues) in issuesByStatus {
                let statusIssues = unsortedStatusIssues.sorted { lhs, rhs in
                    if status == "Open" {
                        let lhsIsNew = pendingNewIssueKeys.contains(lhs.key)
                        let rhsIsNew = pendingNewIssueKeys.contains(rhs.key)
                        if lhsIsNew != rhsIsNew { return lhsIsNew && !rhsIsNew }
                    }
                    return self.issueSortValue(lhs.key) > self.issueSortValue(rhs.key)
                }
                self.menu.addItem(.separator())
                self.menu.addItem(withTitle: status, action: nil, keyEquivalent: "")
                
                for issue in statusIssues {
                    let isNewIssue = pendingNewIssueKeys.contains(issue.key)
                    let issueURL = URL(string: "\(self.baseUrl)/browse/\(issue.key)")!
                    
                    if isNewIssue {
                        let rowItem = NSMenuItem()
                        let rowView = IssueMenuRowView(issue: issue, isAcknowledged: false)
                        rowView.frame = NSRect(x: 0, y: 0, width: 360, height: 52)
                        rowView.onAcknowledgeToggle = { [weak self] isChecked in
                            guard let self else { return }
                            if isChecked {
                                self.acknowledgeIssue(issueKey: issue.key)
                            }
                        }
                        rowView.onOpen = {
                            NSWorkspace.shared.open(issueURL)
                        }
                        rowView.onShowActions = { [weak self] in
                            self?.showIssueActions(for: issue, issueURL: issueURL)
                        }
                        rowItem.view = rowView
                        self.menu.addItem(rowItem)
                    } else {
                        let issueItem = NSMenuItem(title: "", action: #selector(self.openLink), keyEquivalent: "")
                        issueItem.target = self
                        issueItem.attributedTitle = self.makeIssueTitle(for: issue, isNewIssue: false)
                        if issue.fields.summary.count > 50 {
                            issueItem.toolTip = issue.fields.summary
                        }
                        issueItem.representedObject = issueURL
                        
                        self.jiraClient.getTransitionsByIssueKey(issueKey: issue.key) { transitions in
                            if !transitions.isEmpty {
                                issueItem.submenu = self.makeTransitionsMenu(for: issue, issueURL: issueURL, transitions: transitions)
                            }
                        }
                        
                        self.menu.addItem(issueItem)
                    }
                }
            }
            
            self.menu.addItem(.separator())
            let unacknowledgedCount = pendingNewIssueKeys.count
            if unacknowledgedCount > 0 {
                let newIssuesItem = NSMenuItem(title: "\(unacknowledgedCount) new issue\(unacknowledgedCount == 1 ? "" : "s") need acknowledgement", action: nil, keyEquivalent: "")
                newIssuesItem.isEnabled = false
                self.menu.addItem(newIssuesItem)
                
                let acknowledgeAllItem = NSMenuItem(title: "Acknowledge all", action: #selector(self.acknowledgeAllIssues), keyEquivalent: "")
                acknowledgeAllItem.target = self
                acknowledgeAllItem.state = .off
                self.menu.addItem(acknowledgeAllItem)
                
                self.menu.addItem(.separator())
            }
            
            let refreshItem = NSMenuItem(title: "Refresh", action: #selector(self.refreshMenu), keyEquivalent: "")
            refreshItem.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: nil)
            self.menu.addItem(refreshItem)
            
            let openSearchResultsItem = NSMenuItem(title: "Open Search results", action: #selector(self.openSearchResults), keyEquivalent: "")
            openSearchResultsItem.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil)
            self.menu.addItem(openSearchResultsItem)
            
            let createNewItem = NSMenuItem(title: "Create issue", action: #selector(self.openCreateNewIssue), keyEquivalent: "")
            createNewItem.image = NSImage(systemSymbolName: "plus", accessibilityDescription: nil)
            self.menu.addItem(createNewItem)
            
            self.menu.addItem(.separator())
            self.menu.addItem(withTitle: "Preferences...", action: #selector(self.openPrefecencesWindow), keyEquivalent: "")
            self.menu.addItem(withTitle: "About JiraBar", action: #selector(self.openAboutWindow), keyEquivalent: "")
            self.menu.addItem(withTitle: "Quit", action: #selector(self.quit), keyEquivalent: "")
        }
    }
    
    private func issueSortValue(_ issueKey: String) -> Int {
        Int(issueKey.split(separator: "-").last ?? "") ?? 0
    }
    
    private func makeIssueTitle(for issue: Issue, isNewIssue: Bool) -> NSMutableAttributedString {
        let title = NSMutableAttributedString(string: "")
        
        if isNewIssue {
            let newAttributes: [NSAttributedString.Key: Any] = [
                .foregroundColor: NSColor.systemOrange,
                .font: NSFont.boldSystemFont(ofSize: NSFont.systemFontSize)
            ]
            title.append(NSAttributedString(string: "● NEW ", attributes: newAttributes))
        }
        
        title.appendString(string: issue.fields.summary.trunc(length: 50))
            .appendNewLine()
            .appendIcon(iconName: "hash", color: isNewIssue ? .systemOrange : .gray)
            .appendString(string: issue.key, color: isNewIssue ? "#FF8A00" : "#888888")
            .appendSeparator()
            .appendIcon(iconName: "project", color: .gray)
            .appendString(string: issue.fields.assignee?.displayName ?? "Unassign", color: "#888888")
            .appendSeparator()
            .appendString(string: issue.fields.issuetype.name, color: "#888888")
        
        return title
    }
    
    private func makeTransitionsMenu(for issue: Issue, issueURL: URL, transitions: [Transition]) -> NSMenu {
        let issueMenu = NSMenu()
        let openItem = NSMenuItem(title: "Open in Jira", action: #selector(self.openLink), keyEquivalent: "")
        openItem.target = self
        openItem.representedObject = issueURL
        issueMenu.addItem(openItem)
        issueMenu.addItem(.separator())
        
        let header = NSMenuItem(title: "Transition to...", action: nil, keyEquivalent: "")
        issueMenu.addItem(header)
        for transition in transitions {
            let transitionItem = NSMenuItem(title: transition.name, action: #selector(self.transitionIssue), keyEquivalent: "")
            transitionItem.target = self
            transitionItem.representedObject = [issue.key, transition.id]
            issueMenu.addItem(transitionItem)
        }
        return issueMenu
    }
    
    private func showIssueActions(for issue: Issue, issueURL: URL) {
        let actionsMenu = NSMenu()
        let openItem = NSMenuItem(title: "Open in Jira", action: #selector(self.openLink), keyEquivalent: "")
        openItem.target = self
        openItem.representedObject = issueURL
        actionsMenu.addItem(openItem)
        actionsMenu.addItem(.separator())
        let loadingItem = NSMenuItem(title: "Loading transitions...", action: nil, keyEquivalent: "")
        loadingItem.isEnabled = false
        actionsMenu.addItem(loadingItem)
        
        let point = NSPoint(x: 0, y: 0)
        NSMenu.popUpContextMenu(actionsMenu, with: NSApp.currentEvent!, for: statusBarItem.button!)
        _ = point
        
        jiraClient.getTransitionsByIssueKey(issueKey: issue.key) { transitions in
            actionsMenu.removeAllItems()
            actionsMenu.addItem(openItem)
            if transitions.isEmpty {
                let noTransitions = NSMenuItem(title: "No transitions available", action: nil, keyEquivalent: "")
                noTransitions.isEnabled = false
                actionsMenu.addItem(.separator())
                actionsMenu.addItem(noTransitions)
            } else {
                actionsMenu.addItem(.separator())
                let header = NSMenuItem(title: "Transition to...", action: nil, keyEquivalent: "")
                actionsMenu.addItem(header)
                for transition in transitions {
                    let transitionItem = NSMenuItem(title: transition.name, action: #selector(self.transitionIssue), keyEquivalent: "")
                    transitionItem.target = self
                    transitionItem.representedObject = [issue.key, transition.id]
                    actionsMenu.addItem(transitionItem)
                }
            }
        }
    }
    
    private func updateStatusBarAppearance(hasUnacknowledgedNewIssues: Bool) {
        guard let button = statusBarItem.button else { return }
        button.image = normalIcon
        button.contentTintColor = hasUnacknowledgedNewIssues ? .systemOrange : nil
        button.wantsLayer = true
        button.layer?.cornerRadius = 6
        button.layer?.borderWidth = hasUnacknowledgedNewIssues ? 1.5 : 0
        button.layer?.borderColor = hasUnacknowledgedNewIssues ? NSColor.systemOrange.cgColor : NSColor.clear.cgColor
        button.layer?.backgroundColor = hasUnacknowledgedNewIssues ? NSColor.systemOrange.withAlphaComponent(0.12).cgColor : NSColor.clear.cgColor
    }
    
    private func notifyAboutNewIssues(_ issues: [Issue]) {
        guard !issues.isEmpty else { return }
        
        let body: String
        if issues.count == 1, let issue = issues.first {
            body = "\(issue.key): \(issue.fields.summary)"
        } else {
            let preview = issues.prefix(3)
                .map { "\($0.key): \($0.fields.summary)" }
                .joined(separator: "\n")
            let suffix = issues.count > 3 ? "\n…" : ""
            body = "\(issues.count) new issues found\n\(preview)\(suffix)"
        }
        
        sendNotification(body: body)
    }
    
    private func acknowledgeIssue(issueKey: String) {
        pendingNewIssueKeys.removeAll { $0 == issueKey }
        updateStatusBarAppearance(hasUnacknowledgedNewIssues: !pendingNewIssueKeys.isEmpty)
        refreshMenu()
    }
    
    @objc
    func acknowledgeIssue(_ sender: NSMenuItem) {
        guard let issueKey = sender.representedObject as? String else { return }
        acknowledgeIssue(issueKey: issueKey)
    }
    
    @objc
    func acknowledgeAllIssues(_ sender: NSMenuItem) {
        pendingNewIssueKeys.removeAll()
        updateStatusBarAppearance(hasUnacknowledgedNewIssues: false)
        refreshMenu()
    }
    
    @objc
    func transitionIssue(_ sender: NSMenuItem) {
        let issueKeyAndTo = sender.representedObject as! [String]
        jiraClient.transitionIssue(issueKey: issueKeyAndTo[0], to: issueKeyAndTo[1]) {
            self.refreshMenu()
        }
    }
    
    @objc
    func openSearchResults() {
        let encodedPath = jql.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
        NSWorkspace.shared.open(URL(string: "\(baseUrl)/issues?jql=" + encodedPath!)!)
    }
    
    @objc
    func openCreateNewIssue() {
        NSWorkspace.shared.open(URL(string: "\(baseUrl)/secure/CreateIssue!default.jspa")!)
    }
    
    @objc
    func openLink(_ sender: NSMenuItem) {
        NSWorkspace.shared.open(sender.representedObject as! URL)
    }
    
    @objc
    func openPrefecencesWindow(_: NSStatusBarButton?) {
        let contentView = PreferencesView()
        if preferencesWindow != nil { preferencesWindow.close() }
        preferencesWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100), styleMask: [.closable, .titled], backing: .buffered, defer: false)
        preferencesWindow.title = "Preferences"
        preferencesWindow.contentView = NSHostingView(rootView: contentView)
        preferencesWindow.makeKeyAndOrderFront(nil)
        preferencesWindow.styleMask.remove(.resizable)
        NSApplication.shared.activate(ignoringOtherApps: true)
        NSWindowController(window: preferencesWindow).showWindow(self)
        preferencesWindow.center()
        preferencesWindow.orderFrontRegardless()
    }
    
    @objc
    func openAboutWindow(_: NSStatusBarButton?) {
        let contentView = AboutView()
        if aboutWindow != nil { aboutWindow.close() }
        aboutWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 240, height: 340), styleMask: [.closable, .titled], backing: .buffered, defer: false)
        aboutWindow.title = "About"
        aboutWindow.contentView = NSHostingView(rootView: contentView)
        aboutWindow.makeKeyAndOrderFront(nil)
        aboutWindow.styleMask.remove(.resizable)
        NSApplication.shared.activate(ignoringOtherApps: true)
        NSWindowController(window: aboutWindow).showWindow(self)
        aboutWindow.center()
        aboutWindow.orderFrontRegardless()
    }
    
    @objc
    func quit(_: NSStatusBarButton) {
        NSApplication.shared.terminate(self)
    }
    
    @objc
    func windowClosed(notification: NSNotification) {
        let window = notification.object as? NSWindow
        if window?.title == "Preferences" {
            timer?.invalidate()
            timer = Timer.scheduledTimer(timeInterval: Double(refreshRate * 60), target: self, selector: #selector(refreshMenu), userInfo: nil, repeats: true)
            timer?.fire()
        }
    }
    
    @objc
    func checkForUpdates() {
        // Intentionally disabled.
    }
}
