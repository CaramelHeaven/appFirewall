//
//  MainScreen.swift
//  appFirewall
//
//  Created by Sergey Fominov on 10/15/20.
//  Copyright © 2020 Doug Leith. All rights reserved.
//

import SwiftUI

struct MainScreen: View {
    @ObservedObject var viewModel = MainViewModel()

    private func recordProgress() {}

    var body: some View {
        VStack {
            Text("Preferences")

            VStack {
                Image(nsImage: NSImage(named: NSImage.preferencesGeneralName)!)
                Text("Shortcuts")
            }

            Button("Click to kill poe") {
                viewModel.findPoeAndKill()
            }

            Spacer()

            Text("ASD")
        }.frame(maxWidth: 480, maxHeight: 380)
    }
}

struct MainScreen_Previews: PreviewProvider {
    static var previews: some View {
        MainScreen()
    }
}
