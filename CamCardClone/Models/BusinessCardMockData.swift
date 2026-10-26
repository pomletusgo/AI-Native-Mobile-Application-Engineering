import Foundation

/// Week2 使用的 Mock 数据。
///
/// 用途：
/// - SwiftUI Preview；
/// - 扫描入口占位的「模拟识别」结果（用于验证 T12 保存闭环）；
/// - 单元测试的固定样本。
///
/// 数据来源参考 `testcards/ground_truth.json` 中的合成名片定义（不含真实个人信息）。
enum BusinessCardMockData {

    /// 一组用于预览的示例名片。
    static let sampleCards: [BusinessCard] = [
        BusinessCard(
            originalImageName: "tc02_david_chen.jpg",
            processedImageName: "tc02_david_chen_processed.jpg",
            name: "David Chen",
            company: "ABC Technologies",
            jobTitle: "Technical Director",
            mobile: "+1-555-0100",
            email: "david.chen@example.com",
            website: "www.example.com",
            tags: ["Conference"],
            notes: "2026 Mobile Computing Conference",
            createdAt: Date(timeIntervalSince1970: 1_730_000_000)
        ),
        BusinessCard(
            originalImageName: "tc03_li_na.jpg",
            name: "李娜",
            company: "环宇国际贸易有限公司",
            jobTitle: "市场经理",
            mobile: "139-0000-0002",
            phone: "021-6000-1000",
            email: "lina@example.com",
            address: "上海市静安区南京西路500号",
            tags: ["Customer"],
            createdAt: Date(timeIntervalSince1970: 1_730_100_000)
        ),
        BusinessCard(
            originalImageName: "tc11_zhu_hongming.jpg",
            name: "朱宏明",
            company: "同济大学",
            jobTitle: "教授",
            phone: "021-6598-0000",
            email: "zhuhongming@example.edu.cn",
            address: "上海市杨浦区四平路1239号",
            tags: ["Professor"],
            createdAt: Date(timeIntervalSince1970: 1_730_200_000)
        )
    ]

    /// 扫描入口占位使用的「模拟识别结果」。
    ///
    /// Week3 接入真实 OCR 后，本方法将被 `OCRService` + `BusinessCardFieldParser` 的输出取代；
    /// 同时**不得修改** `BusinessCard` 与 `BusinessCardRepository` 的既有接口。
    static func makeRecognizedCard() -> BusinessCard {
        BusinessCard(
            originalImageName: "mock_scan.jpg",
            processedImageName: "mock_scan_processed.jpg",
            name: "王小明",
            company: "示例科技有限公司",
            jobTitle: "产品经理",
            mobile: "138-0000-9999",
            email: "wangxiaoming@example.com",
            tags: [],
            createdAt: Date()
        )
    }
}
