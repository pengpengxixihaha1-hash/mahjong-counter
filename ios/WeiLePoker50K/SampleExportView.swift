import SwiftUI
import UniformTypeIdentifiers

// 样本导出：把 App Group 容器中的对局帧样本复制到 Documents/样本，
// 再弹系统文档选择器让用户「存储到文件」，或用 iTunes/Apple Devices 文件共享拷到电脑。
struct SampleExportView: UIViewControllerRepresentable {
    let dirURL: URL

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forExporting: [dirURL], asCopy: true)
        picker.allowsMultipleSelection = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
}
