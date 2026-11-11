import AppKit

@MainActor enum AppMenus {
    static func install(settingsTarget: AnyObject, settingsAction: Selector) {
        let main = NSMenu()
        func submenu(_ title: String) -> NSMenu {
            let menu = NSMenu(title: title)
            let item = NSMenuItem()
            item.submenu = menu
            main.addItem(item)
            return menu
        }
        func item(_ menu: NSMenu, _ title: String, _ action: String, _ key: String = "",
                  target: AnyObject? = nil, modifiers: NSEvent.ModifierFlags = .command) {
            let entry = menu.addItem(withTitle: title, action: NSSelectorFromString(action), keyEquivalent: key)
            entry.target = target
            entry.keyEquivalentModifierMask = modifiers
        }

        let app = submenu("Keydown")
        item(app, "About Keydown", "orderFrontStandardAboutPanel:", target: NSApp)
        app.addItem(.separator())
        item(app, "Settings…", NSStringFromSelector(settingsAction), ",", target: settingsTarget)
        let services = NSMenu(title: "Services")
        let servicesItem = NSMenuItem(title: "Services", action: nil, keyEquivalent: "")
        servicesItem.submenu = services
        app.addItem(servicesItem)
        NSApp.servicesMenu = services
        app.addItem(.separator())
        item(app, "Hide Keydown", "hide:", "h", target: NSApp)
        item(app, "Hide Others", "hideOtherApplications:", "h", target: NSApp, modifiers: [.command, .option])
        item(app, "Show All", "unhideAllApplications:", target: NSApp)
        app.addItem(.separator())
        item(app, "Quit Keydown", "terminate:", "q", target: NSApp)

        let file = submenu("File")
        item(file, "Close Window", "performClose:", "w")
        item(file, "Save", "saveCurrentDraft:", "s")

        let edit = submenu("Edit")
        item(edit, "Undo", "undo:", "z")
        item(edit, "Redo", "redo:", "z", modifiers: [.command, .shift])
        edit.addItem(.separator())
        item(edit, "Cut", "cut:", "x")
        item(edit, "Copy", "copy:", "c")
        item(edit, "Paste", "paste:", "v")
        item(edit, "Select All", "selectAll:", "a")

        let window = submenu("Window")
        item(window, "Minimize", "performMiniaturize:", "m")
        item(window, "Zoom", "performZoom:")
        window.addItem(.separator())
        item(window, "Bring All to Front", "arrangeInFront:", target: NSApp)
        NSApp.windowsMenu = window
        NSApp.mainMenu = main
    }
}
