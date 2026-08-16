//
//  Dangerous Dave 2: The Relic Retrieval — native macOS shell
//
//  A minimal AppKit host around a WKWebView that renders the self-contained
//  index.html game bundled in Contents/Resources. No third-party dependencies.
//

import Cocoa
import WebKit

final class GameApp: NSObject, NSApplicationDelegate, WKNavigationDelegate, WKUIDelegate {

    private var window: NSWindow!
    private var webView: WKWebView!
    private var devMenuItem: NSMenuItem?

    /// Dev mode survives relaunches, so you only toggle it once per machine.
    /// `--dev` on the command line forces it on for a single run.
    private var devModeEnabled: Bool {
        get {
            CommandLine.arguments.contains("--dev")
                || UserDefaults.standard.bool(forKey: "devMode")
        }
        set { UserDefaults.standard.set(newValue, forKey: "devMode") }
    }

    /// The game renders at 320x240 internally and floor-scales to fit.
    /// 1024x768 lands exactly on a 3x integer scale with a thin black border.
    private let defaultContentSize = NSSize(width: 1024, height: 768)

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenuBar()
        buildWindow()
        loadGame()
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    // MARK: - Window

    private func buildWindow() {
        let config = WKWebViewConfiguration()
        // Web Audio is gesture-gated by the game itself, but clear the media
        // restriction so the AudioContext resumes on the first key press.
        config.mediaTypesRequiringUserActionForPlayback = []

        // Kill the right-click menu and image dragging so it behaves like a game,
        // not a web page.
        let tidyUp = WKUserScript(
            source: """
                document.addEventListener('contextmenu', e => e.preventDefault());
                document.addEventListener('dragstart',  e => e.preventDefault());
                """,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
        config.userContentController.addUserScript(tidyUp)

        let frame = NSRect(origin: .zero, size: defaultContentSize)
        webView = WKWebView(frame: frame, configuration: config)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.autoresizingMask = [.width, .height]
        webView.underPageBackgroundColor = .black
        webView.allowsBackForwardNavigationGestures = false

        window = NSWindow(
            contentRect: frame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Dangerous Dave 2: The Relic Retrieval"
        window.backgroundColor = .black
        window.contentAspectRatio = NSSize(width: 4, height: 3)
        window.contentMinSize = NSSize(width: 640, height: 480)
        window.contentView = webView
        window.center()
        window.setFrameAutosaveName("DangerousDave2MainWindow")
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(webView)
    }

    private func loadGame() {
        guard let html = Bundle.main.url(forResource: "index", withExtension: "html") else {
            presentFatal("index.html is missing from the application bundle.")
            return
        }
        // Loaded over file:// so the page keeps a real origin, matching the
        // environment the game was tested in.
        webView.loadFileURL(html, allowingReadAccessTo: html.deletingLastPathComponent())
    }

    private func presentFatal(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Dangerous Dave 2 could not start"
        alert.informativeText = message
        alert.alertStyle = .critical
        alert.runModal()
        NSApp.terminate(nil)
    }

    // MARK: - Menu bar

    private func buildMenuBar() {
        let appName = "Dangerous Dave 2"
        let mainMenu = NSMenu()

        // Application menu
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About \(appName)",
                        action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
                        keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide \(appName)",
                        action: #selector(NSApplication.hide(_:)),
                        keyEquivalent: "h")
        let hideOthers = appMenu.addItem(withTitle: "Hide Others",
                                         action: #selector(NSApplication.hideOtherApplications(_:)),
                                         keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit \(appName)",
                        action: #selector(NSApplication.terminate(_:)),
                        keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        // Game menu
        let gameMenuItem = NSMenuItem()
        let gameMenu = NSMenu(title: "Game")
        gameMenu.addItem(withTitle: "Restart Level",
                         action: #selector(restartLevel),
                         keyEquivalent: "r")
        gameMenu.addItem(withTitle: "Back to Title Screen",
                         action: #selector(backToTitle),
                         keyEquivalent: "t")
        gameMenu.addItem(.separator())
        gameMenu.addItem(withTitle: "Mute / Unmute",
                         action: #selector(toggleMute),
                         keyEquivalent: "m")
        gameMenuItem.submenu = gameMenu
        mainMenu.addItem(gameMenuItem)

        // View menu
        let viewMenuItem = NSMenuItem()
        let viewMenu = NSMenu(title: "View")
        let fullScreen = viewMenu.addItem(withTitle: "Enter Full Screen",
                                          action: #selector(NSWindow.toggleFullScreen(_:)),
                                          keyEquivalent: "f")
        fullScreen.keyEquivalentModifierMask = [.command, .control]
        viewMenu.addItem(.separator())
        viewMenu.addItem(withTitle: "Actual Size (3x)",
                         action: #selector(resetWindowSize),
                         keyEquivalent: "0")
        viewMenuItem.submenu = viewMenu
        mainMenu.addItem(viewMenuItem)

        // Developer menu — the level selector is hidden until this is on.
        let devMenuItem = NSMenuItem()
        let devMenu = NSMenu(title: "Developer")
        let toggle = devMenu.addItem(withTitle: "Level Select on Title Screen",
                                     action: #selector(toggleDevMode),
                                     keyEquivalent: "d")
        toggle.keyEquivalentModifierMask = [.command, .shift]
        toggle.state = devModeEnabled ? .on : .off
        self.devMenuItem = toggle
        devMenu.addItem(.separator())
        devMenu.addItem(withTitle: "Back to Title Screen to Pick a Level",
                        action: #selector(backToTitle),
                        keyEquivalent: "")
        devMenuItem.submenu = devMenu
        mainMenu.addItem(devMenuItem)

        NSApp.mainMenu = mainMenu
    }

    @objc private func toggleDevMode() {
        let now = !devModeEnabled
        devModeEnabled = now
        devMenuItem?.state = now ? .on : .off
        applyDevMode()
    }

    /// Pushes the current dev-mode setting into the page.
    private func applyDevMode() {
        webView.evaluateJavaScript("ddSetDevMode(\(devModeEnabled))", completionHandler: nil)
    }

    // MARK: - Menu actions
    //
    // These drive the game by synthesising the keystrokes its own input handler
    // already listens for, so the web layer needs no app-specific code.

    private func sendKey(_ key: String) {
        let js = """
            (() => {
              const opts = { key: '\(key)', bubbles: true };
              window.dispatchEvent(new KeyboardEvent('keydown', opts));
              setTimeout(() => window.dispatchEvent(new KeyboardEvent('keyup', opts)), 40);
            })()
            """
        webView.evaluateJavaScript(js, completionHandler: nil)
    }

    @objc private func restartLevel() { sendKey("r") }
    @objc private func toggleMute()   { sendKey("m") }

    @objc private func backToTitle() {
        webView.evaluateJavaScript(
            "game.state = STATE.START; game.titleT = 0; game.score = 0; game.lives = 3; game.relicsCollected = 0;",
            completionHandler: nil
        )
    }

    @objc private func resetWindowSize() {
        guard let window = window else { return }
        if window.styleMask.contains(.fullScreen) { window.toggleFullScreen(nil) }
        window.setContentSize(defaultContentSize)
        window.center()
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // The canvas must own the keyboard for arrow keys and space to reach it.
        window.makeFirstResponder(webView)

        // Restore the persisted dev-mode setting into the freshly loaded page.
        applyDevMode()

        if CommandLine.arguments.contains("--selftest") { runSelfTest() }
    }

    // MARK: - Self-test
    //
    // `DangerousDave2.app/Contents/MacOS/DangerousDave2 --selftest` boots the real
    // WKWebView, exercises the game inside it, prints a report and exits. Used to
    // verify the bundle without needing a human at the screen.

    private func runSelfTest() {
        let probe = """
            (() => {
              const r = {};
              try {
                r.title        = document.title;
                r.levels       = (typeof LEVELS !== 'undefined') ? LEVELS.length : -1;
                r.canvas2d     = !!(document.getElementById('c') || {}).getContext
                                 && !!document.getElementById('c').getContext('2d');
                r.pixelated    = getComputedStyle(document.getElementById('c')).imageRendering;
                r.audioCtor    = !!(window.AudioContext || window.webkitAudioContext);
                r.startState   = game.state;
                r.devMode      = window.ddIsDevMode();   // reflects the persisted/--dev setting

                // Boot level 1 and run a second of real frames.
                startLevel(0);
                r.levelName    = level.def.name;
                r.enemies      = level.enemies.length;
                for (let i = 0; i < 60; i++) update(1/60);
                r.playerOnFloor = player.grounded;
                r.noClip        = !boxHitsSolid(player.x+1, player.y+1, player.w-2, player.h-2);

                // Relic -> door -> transition, inside the app's own web view.
                const relic = level.pickups.find(p => p.kind === 'R');
                player.x = relic.x + 2; player.y = relic.y; update(1/60);
                r.doorUnlocked = level.door.open;

                // Confirm an AudioContext can actually be created here.
                const AC2 = new (window.AudioContext || window.webkitAudioContext)();
                r.audioState = AC2.state;
                AC2.close();

                // Keyboard reachability: the document must hold focus, and the
                // game's own listeners must respond to a real KeyboardEvent.
                r.docFocused = document.hasFocus();
                game.state = STATE.PLAYING;
                const before = player.x;
                window.dispatchEvent(new KeyboardEvent('keydown', {key:'ArrowRight', bubbles:true}));
                for (let i = 0; i < 20; i++) update(1/60);
                window.dispatchEvent(new KeyboardEvent('keyup', {key:'ArrowRight', bubbles:true}));
                r.movedOnKey = player.x > before;

                r.ok = r.levels === 10 && r.canvas2d && r.doorUnlocked
                       && r.noClip && r.movedOnKey && r.docFocused;
              } catch (e) { r.error = e.message; r.ok = false; }
              return JSON.stringify(r);
            })()
            """
        webView.evaluateJavaScript(probe) { result, error in
            if let error = error {
                print("SELFTEST FAILED: \(error.localizedDescription)")
                exit(1)
            }
            let text = (result as? String) ?? "no result"
            // Confirm from the AppKit side that the web view owns the keyboard.
            let responder = self.window.firstResponder
            let ownsKeys = (responder === self.webView)
                || (responder as? NSView)?.isDescendant(of: self.webView) == true
            print("SELFTEST \(text)")
            print("SELFTEST firstResponder=\(type(of: responder as Any)) webViewOwnsKeyboard=\(ownsKeys)")
            exit(text.contains("\"ok\":true") && ownsKeys ? 0 : 1)
        }
    }

    func webView(_ webView: WKWebView,
                 didFail navigation: WKNavigation!,
                 withError error: Error) {
        presentFatal(error.localizedDescription)
    }

    /// Keep every navigation inside the app; the game never needs to leave the page.
    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if navigationAction.navigationType == .linkActivated,
           let url = navigationAction.request.url {
            NSWorkspace.shared.open(url)
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }
}

// MARK: - Entry point

let app = NSApplication.shared
let delegate = GameApp()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
