//
//  main.swift
//  appFirewall
//
//  Created by Sergey Fominov on 10/15/20.
//  Copyright © 2020 Doug Leith. All rights reserved.
//

import Cocoa

let delegate = AppDelegate()
NSApplication.shared.delegate = delegate

_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
