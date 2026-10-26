import SwiftUI

/// 名片夹空状态（状态 S1）。
///
/// 对应 T01：首次启动 → 名片夹 → 正确显示空状态。
struct EmptyCardHolderView: View {

    let onScan: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.text.rectangle")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)

            Text("还没有名片")
                .font(.title3)
                .fontWeight(.semibold)

            Text("扫描或导入一张名片，开始建立你的名片夹")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button {
                onScan()
            } label: {
                Label("扫描第一张名片", systemImage: "camera.viewfinder")
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("emptyStateScanButton")
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("emptyCardHolder")
    }
}

#Preview {
    EmptyCardHolderView {}
}
