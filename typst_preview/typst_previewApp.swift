//
//  typst_previewApp.swift
//  typst_preview
//
//  Created by Hua on 1/7/26.
//

import SwiftUI

@main
struct typst_previewApp: App {
    @StateObject private var downloaderDaemon = DownloaderDaemon()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(downloaderDaemon)
        }
        .handlesExternalEvents(matching: ["*"])
    }
}
