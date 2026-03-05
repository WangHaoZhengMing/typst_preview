//
//  ContentView.swift
//  typst_preview
//
//  Created by Wanghaozhengming on 1/7/26.
//

import SwiftUI

struct ContentView: View {
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
    }
}
        


