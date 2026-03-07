//
//  ContentView.swift
//  typst_preview
//
//  Created by Wanghaozhengming on 1/7/26.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var downloaderDaemon: DownloaderDaemon
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "doc.text.fill")
                .font(.system(size: 60))
                .foregroundColor(.blue)
            
            Text("Typst 预览")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Text("macOS QuickLook 扩展")
                .font(.title3)
                .foregroundColor(.secondary)
            
            Text("快速预览 Typst 文档")
                .font(.body)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
        .onOpenURL { url in
            guard url.scheme == "typstpreview",
                  url.host == "download",
                  let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                  let pkgsParam = components.queryItems?.first(where: { $0.name == "pkgs" })?.value else { return }
            
            let packages = pkgsParam
                .components(separatedBy: ",")
                .compactMap { pkgStr -> (namespace: String, package: String, version: String)? in
                    let parts = pkgStr.components(separatedBy: "/")
                    guard parts.count == 3 else { return nil }
                    return (namespace: parts[0], package: parts[1], version: parts[2])
                }
            downloaderDaemon.downloadPackages(packages)
        }
    }
}
        


