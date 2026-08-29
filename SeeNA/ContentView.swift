//
//  ContentView.swift
//  SeeNA
//
//  Created by Suryateja Challa on 29/8/2026.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        RootView()
    }
}

#Preview {
    ContentView()
        .environmentObject(AppSession())
        .environmentObject(AppDependencies.preview())
}
