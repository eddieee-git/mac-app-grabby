import AppKit
import SwiftUI

/// 처음 실행할 때 보여 주는 안내: 화면 기록 권한, 단축키, 쓰는 방법. 메뉴바의 '시작 안내'로 다시 열 수 있다.
final class WelcomeWindowController {
    private var window: NSWindow?

    func show() {
        if window == nil {
            let controller = NSHostingController(rootView: WelcomeView { [weak self] in self?.window?.close() })
            controller.sizingOptions = .preferredContentSize
            let w = NSWindow(contentViewController: controller)
            w.styleMask = [.titled, .closable]
            w.title = L("Grabby 시작 안내")
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

private struct WelcomeView: View {
    let close: () -> Void
    @ObservedObject private var settings = AppSettings.shared
    @State private var hasPermission = ScreenCapturer.hasPermission
    @State private var blocked = HotKeyConflicts.blockedBySystem(AppSettings.shared.hotKeys)
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("Grabby에 오신 걸 환영해요")).font(.title2.bold())
                    Text(L("메뉴바에 있는 캡처 앱이에요. 찍고, 그리고, 바로 붙여 넣으세요.")).foregroundStyle(.secondary)
                }
            }

            GroupBox {
                HStack {
                    Image(systemName: hasPermission ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                        .foregroundStyle(hasPermission ? .green : .orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("1. 화면 기록 권한")).bold()
                        Text(hasPermission ? L("켜져 있어요.") : L("시스템 설정에서 Grabby를 켜고 \"켰으면 다시 시작\"을 눌러 주세요. 업데이트한 뒤라면 이미 켜져 있어도 한 번 껐다 켜야 할 수 있어요."))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if !hasPermission {
                        VStack(alignment: .trailing, spacing: 4) {
                            Button(L("권한 켜기")) { ScreenCapturer.requestPermission() }
                            Button(L("켰으면 다시 시작")) { NSApp.sendAction(Selector(("relaunch")), to: nil, from: nil) }
                        }
                    }
                }
                .padding(4)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L("2. 단축키")).bold()
                    ForEach(HotKeyAction.allCases, id: \.self) { action in
                        HStack {
                            Text(action.title)
                            Spacer()
                            Text(settings.hotKeys[action.rawValue]?.displayText ?? L("없음"))
                                .font(.system(.body, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(4)
            }

            if !blocked.isEmpty {
                GroupBox {
                    HStack {
                        Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L("macOS 스크린샷 단축키 끄기")).bold()
                            Text(L("%@는 macOS 스크린샷 단축키와 겹쳐요. 키보드 단축키 > 스크린샷에서 그 항목을 꺼 주세요.", blocked.joined(separator: ", ")))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 4) {
                            Button(L("설정 열기")) { HotKeyConflicts.openSystemShortcutSettings() }
                            Button(L("⌃⌘ 키로 바꾸기")) { settings.hotKeys = KeyCombo.controlCommandSet }
                                .help(L("macOS 단축키를 끄지 않고, Grabby 단축키를 모두 ⌃⌘1~5, ⌃⌘₩로 바꿔요."))
                        }
                    }
                    .padding(4)
                }
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L("3. 쓰는 방법")).bold()
                    Text(L("• 드래그해서 영역을 고르거나, 클릭해서 창을 골라요."))
                    Text(L("• 고른 자리에서 바로 그리고, ↩로 복사해요. 원래 앱에서 바로 ⌘V로 붙여 넣으면 돼요."))
                    Text(L("• 캡처는 Grabby 창에 탭으로 쌓여요. 나중에 다시 고치거나 복사할 수 있어요."))
                    Text(L("• 캡처 중에 ?를 누르면 모든 단축키를 볼 수 있어요."))
                }
                .font(.callout)
                .padding(4)
            }

            HStack {
                Button(L("설정 열기")) {
                    NSApp.sendAction(Selector(("openSettings")), to: nil, from: nil)
                }
                Spacer()
                Button(L("시작하기"), action: close).keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 460)
        .onReceive(timer) { _ in
            hasPermission = ScreenCapturer.hasPermission
            blocked = HotKeyConflicts.blockedBySystem(settings.hotKeys)
        }
    }
}
