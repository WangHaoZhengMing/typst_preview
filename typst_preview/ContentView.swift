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
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                statusCard
                queueCard
                installedPackagesCard
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24)
        }
        .frame(minWidth: 720, minHeight: 560)
        .background(Color(nsColor: .windowBackgroundColor))
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
        .onAppear {
            downloaderDaemon.refreshInstalledPackages()
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.blue.opacity(0.9), Color.cyan.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 72, height: 72)

                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Typst Preview Host")
                    .font(.system(size: 28, weight: .bold))

                Text("负责接收 Quick Look 请求、下载依赖包并维护共享缓存。")
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button("刷新包列表") {
                downloaderDaemon.refreshInstalledPackages()
            }
        }
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("当前状态")
                .font(.headline)

            statusRow(title: "最近事件", value: downloaderDaemon.lastEvent)
            statusRow(title: "当前包", value: downloaderDaemon.currentPackage?.displayName ?? "空闲")
            statusRow(title: "待处理数量", value: "\(downloaderDaemon.queuedPackages.count)")
            statusRow(title: "已安装数量", value: "\(downloaderDaemon.installedPackages.count)")

            if let lastRequestAt = downloaderDaemon.lastRequestAt {
                statusRow(
                    title: "最近请求",
                    value: lastRequestAt.formatted(date: .abbreviated, time: .standard)
                )
            }

            if let lastError = downloaderDaemon.lastError {
                VStack(alignment: .leading, spacing: 8) {
                    Text("最近错误")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.red)
                    Text(lastError)
                        .font(.system(size: 13))
                        .foregroundColor(.primary)
                        .textSelection(.enabled)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.red.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
    }

    private var queueCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("下载队列")
                .font(.headline)

            if downloaderDaemon.queuedPackages.isEmpty {
                Text("当前没有待处理下载。")
                    .foregroundColor(.secondary)
            } else {
                ForEach(downloaderDaemon.queuedPackages) { package in
                    packageRow(package)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
    }

    private var installedPackagesCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("已安装包")
                .font(.headline)

            if downloaderDaemon.installedPackages.isEmpty {
                Text("共享缓存中还没有包。")
                    .foregroundColor(.secondary)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], spacing: 12) {
                    ForEach(downloaderDaemon.installedPackages) { package in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(package.package)
                                .font(.system(size: 15, weight: .semibold))
                            Text(package.namespace)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.secondary)
                            Text(package.version)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.blue)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(Color.blue.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(Color(nsColor: .controlBackgroundColor))
    }

    private func statusRow(title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
    }

    private func packageRow(_ package: PackageDescriptor) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(package.displayName)
                    .font(.system(size: 14, weight: .medium))
                Text("等待下载或依赖扫描")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            Spacer()
            if downloaderDaemon.currentPackage == package {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(.vertical, 6)
    }
}
        


