//
//  ContentView.swift
//  SeeNA
//
//  Created by Suryateja Challa on 29/8/2026.
//

import SwiftUI

struct ContentView: View {
    @State private var isShowingLaunchScreen = true

    var body: some View {
        ZStack {
            if isShowingLaunchScreen {
                LaunchScreenView {
                    withAnimation(.easeInOut(duration: 0.24)) {
                        isShowingLaunchScreen = false
                    }
                }
                .transition(.opacity)
                .zIndex(1)
            } else {
                RootView()
                    .transition(.opacity)
            }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppSession())
        .environmentObject(AppDependencies.preview())
}
