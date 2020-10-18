//
//  AppDelegate.swift
//  appFirewall
//
//  Copyright © 2019 Doug Leith. All rights reserved.
//

import Cocoa
import os
import ServiceManagement
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    // --------------------------------------------------------
    // private variables
    // timer for periodic polling ...
    var timer: Timer = Timer()
    var count_stats: Int = 0

    private var window: NSWindow!
    var statusBarItem: NSStatusItem!
    var statusBarMenu: NSMenu!

    @objc func openapp(_ sender: Any?) {
        // reopen window

        // if window already exists,and it should since we don't
        // release it on close, then we just reopen it.
        // hopefully this should work almost all of the time
        // (seems like an error if it doesn't work)
        for window in NSApp.windows {
            print(window, window.title)
            // as well as the main window the status bar button has a window
            if window.title == "appFirewall" {
                print("openapp() restoring existing window")
                window.makeKeyAndOrderFront(self) // bring to front

                NSApp.activate(ignoringOtherApps: true)
                return
            }
        }
        print("WARNING: openapp() falling back to creating new window")
    }

    @objc func refresh() {
        // note: state is saved on window close, no need to do it here
        // (and if we do it here it might be interrupted by a window
        // close event and lead to file corruption

        // check if listener thread (for talking with helper process that
        // has root privilege) has run into trouble -- if so, its fatal
        if Int(check_for_error()) != 0 {
            print("CRUSH")
//            exit_popup(msg: String(cString: get_error_msg()), force: Int(get_error_force()))
            // this call won't return
        }
    }

    let hotKey = HotKey(key: .r, modifiers: [.option])
    let grave = HotKey(key: .grave, modifiers: [])
    let pidWatcher = PidWatcher.shared

    func applicationWillFinishLaunching(_ aNotification: Notification) {
        initMyShit()

        statusBarItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusBarItem.button?.title = "FUCK"

        statusBarMenu = NSMenu()
        statusBarMenu.delegate = self

        statusBarMenu.addItem(withTitle: "Is poe connected?", action: nil, keyEquivalent: "")
        statusBarMenu.addItem(withTitle: "Preferences", action: #selector(showPreferences(_:)), keyEquivalent: "")
        statusBarMenu.addItem(NSMenuItem.separator())

        statusBarMenu.addItem(withTitle: "Quit", action: #selector(quit(_:)), keyEquivalent: "")

        statusBarItem.menu = statusBarMenu
        
        let contentView = MainScreen()
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
                          styleMask: [.titled, .closable, .resizable],
                          backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.center()
        window.setFrameAutosaveName("Main Window")
        window.contentView = NSHostingView(rootView: contentView)

        window.makeKeyAndOrderFront(nil)

        hotKey.keyDownHandler = {
            print("Pressed ⌥⌘R at \(Date())")
        }

        grave.keyDownHandler = {
            self.pidWatcher.resetPoe()
        }

    }

    @objc func showPreferences(_ sender: NSStatusBarButton) {
        let contentView = MainScreen()
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 300),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                          backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.center()
        window.setFrameAutosaveName("Main Window")
        window.contentView = NSHostingView(rootView: contentView)

        window.makeKeyAndOrderFront(nil)
    }

    @objc func quit(_ sender: NSStatusBarButton) {
        NSApplication.shared.terminate(self)
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        print("stopping")
        // viewWillDisappear() event is triggered for any open windows
        // and will call save_state(), so no need to do it again here
        stop_helper_listeners()
        if Config.getBlockQUIC() { unblock_QUIC() }
        if Config.getDnscrypt_proxy() { stop_dnscrypt_proxy() }
    }

    func applicationDidEnterBackground(_ aNotification: Notification) {
        // Insert code here to tear down your application
        // NB: don't think this function is *ever* called
        print("going into background")
    }

    func applicationShouldHandleReopen(_ sender: NSApplication,
                                       hasVisibleWindows flag: Bool) -> Bool {
        // called when click on dock icon to reopen window
        openapp(nil)
        return true
    }

    func initMyShit() {
        init_stats() // must be done before any C threads are fired up

        // set up handler to catch errors.
        setup_sig_handlers()

        // install appFirewall-Helper, if not already installed
        UserDefaults.standard.register(defaults: ["force_helper_restart": false])
        let force = UserDefaults.standard.bool(forKey: "force_helper_restart")
        start_helper(force: force)
        // reset, force is one time only
        UserDefaults.standard.set(false, forKey: "force_helper_restart")

        usefullUtilities()

        // refresing listener thread (for talking with helper process that) for stabillity I assumed?
        timer = Timer.scheduledTimer(timeInterval: Config.appDelegateRefreshTime, target: self, selector: #selector(refresh), userInfo: nil, repeats: true)
        timer.tolerance = 1 // we don't mind if it runs quite late
    }
}

// MARK: - Usefull? ??

extension AppDelegate {
    func usefullUtilities() {
        let sipEnabled = isSIPEnabled()
        print("SIP enabled: ", sipEnabled)

        var dtrace = UserDefaults.standard.integer(forKey: "dtrace")
        if sipEnabled { dtrace = 0 } // dtrace doesn't work with SIP
        let nstat = UserDefaults.standard.integer(forKey: "nstat")

        print("D TRANCE ENABLE: \(dtrace > 0)")
        print("N ENABLE?: \(nstat > 0)")

        // reload state
        // Important String which helps us to GET item from blocklist in here
        // -> get_connlist_item(get_blocklist(),Int32(0))
        load_state()
        Config.initLoad()

        // start listeners
        // this can be slow since it blocks while making network connection to helper
        DispatchQueue.global(qos: .background).async {
            start_helper_listeners(Int32(dtrace), Int32(nstat))
        }
    }
}

// MARK: - Logging from C, not usefull but I dont remove it yet

extension AppDelegate {
    func logFromC() {
        make_data_dir()

        // redirect C logging from stdout to logfile.  do this early but
        // important to call make_data_dir() first so that logfile has somewhere to live
        redirect_stdout(Config.appLogName)

        // set default logging level, again do this early
        UserDefaults.standard.register(defaults: ["logging_level": Config.defaultLoggingLevel])
        // can change this at command line using "defaults write" command
        let log_level = UserDefaults.standard.integer(forKey: "logging_level")
        set_logging_level(Int32(log_level))
    }

    func uselessDebug() {
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        print("appFirewall version: ", appVersion ?? "<not found>")
        print("process: ")
        print("environment ", ProcessInfo.processInfo.environment)

        UserDefaults.standard.register(defaults: ["signal": -1])
        UserDefaults.standard.register(defaults: ["logcrashes": 1])
        let sig = UserDefaults.standard.integer(forKey: "signal")
        if sig > 0 {
            // we had a crash !
            if let backtrace = UserDefaults.standard.object(forKey: "backtrace") as? [String], let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
                print("CRUSH: \(backtrace), CRUS: \(version)")
            } else {
                print("problem getting backtrace or version from userdefaults after crash")
            }
        }
    }
}

// MARK: - DO NOT REMOVE

func load_state() {
    load_log(Config.logName, Config.logTxtName)
    load_connlist(get_blocklist(), Config.blockListName); load_connlist(get_whitelist(), Config.whiteListName)
    load_dns_cache(Config.dnsName)
    // we distribute app with preconfigured dns_conn cache so that
    // can guess process names of common apps more quickly
    let filePath = String(cString: get_path())
    let backupPath = Bundle.main.resourcePath ?? "./"
    if load_dns_conn_list(filePath, Config.dnsConnListName) < 0 {
        print("Falling back to loading dns_conn_list from ", backupPath)
        load_dns_conn_list(backupPath, Config.dnsConnListName)
    }
}
