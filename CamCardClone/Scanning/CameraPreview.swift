import AVFoundation
import SwiftUI

/// 相机取景预览层。
///
/// 只负责把采集会话显示出来，不参与权限申请与拍摄：会话由 `AVCapturePhotoCapturer` 持有，
/// 拍摄动作也由它发起，这样「能不能用相机」「拍成什么样」都可以脱离界面单独验证。
struct CameraPreviewView: UIViewRepresentable {

    /// 采集会话，通常来自 `AVCapturePhotoCapturer.previewSession`。
    let session: AVCaptureSession

    func makeUIView(context: Context) -> CameraPreviewLayerView {
        let view = CameraPreviewLayerView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: CameraPreviewLayerView, context: Context) {
        uiView.previewLayer.session = session
    }
}

/// 取景视图：以 `layerClass` 让视图自带的 layer 就是预览层，尺寸与屏幕旋转交由系统处理。
final class CameraPreviewLayerView: UIView {

    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    var previewLayer: AVCaptureVideoPreviewLayer {
        guard let layer = layer as? AVCaptureVideoPreviewLayer else {
            fatalError("layerClass 已固定为 AVCaptureVideoPreviewLayer")
        }
        return layer
    }
}
