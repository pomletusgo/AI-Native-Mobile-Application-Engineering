import SwiftUI

/// 扫描名片入口（P02 占位页）。
///
/// Week2 范围：仅提供入口，用于验证 T02（名片夹 → 扫描 → 进入相机页面）。
/// Week3 将在此接入：相机预览、权限申请、拍摄/取消/重拍、相册导入，并连接 P03–P05 流程。
///
/// 为验证 T12（确认 → 保存 → 返回名片夹 → 出现新名片），本周提供「模拟识别并保存」。
/// 该入口最终会被真实识别结果替换，且不会修改 `BusinessCard` / `BusinessCardRepository` 接口。
struct ScannerEntryView: View {

    let repository: BusinessCardRepository

    @EnvironmentObject private var router: AppRouter

    init(repository: BusinessCardRepository) {
        self.repository = repository
    }

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)

            Text("拍摄名片")
                .font(.title3)
                .fontWeight(.semibold)

            Text("相机、图片导入、名片区域检测与 OCR 将在 Week3 接入。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button {
                repository.add(BusinessCardMockData.makeRecognizedCard())
                router.popToRoot()
            } label: {
                Label("模拟识别并保存名片", systemImage: "wand.and.stars")
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("simulateRecognizeButton")

            Button("取消") {
                router.pop()
            }
            .accessibilityIdentifier("scannerCancelButton")
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("扫描名片")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("scannerEntry")
    }
}

#Preview {
    NavigationStack {
        ScannerEntryView(repository: InMemoryBusinessCardRepository())
    }
    .environmentObject(AppRouter())
}
