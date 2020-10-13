//
//  MainScreen.swift
//  MacLogout
//
//  Created by Sergey Fominov on 10/13/20.
//  Copyright © 2020 Doug Leith. All rights reserved.
//

import SwiftUI

struct MainScreen: View {
    @ObservedObject var viewModel = MainViewModel()

    var body: some View {
        ZStack {
            Text("TEST")
            
            Button("Block poe") {
                viewModel.findAndBlockPoe()
            }
            
        }.frame(width: 200, height: 200)
    }
}
