#if os(iOS)
import Foundation
import WebKit
import PDFKit

/// pptx → PDF dönüşümü, tamamen cihazda (iOS WebKit), bulut yok.
///
/// Neden böyle: iPad'de pptx'i doğrudan PDF'e çeviren bir sistem API'si yok;
/// LibreOffice-WASM iPad belleği için fazla ağır, native port ise devasa bir
/// iş. Fizibilite denemesi gösterdi ki hafif bir JS renderer (`pptx-preview`)
/// görünmez bir `WKWebView` içinde slaytları çiziyor, oradan slayt-başına
/// `createPDF` ile metin katmanlı, çok-sayfalı PDF üretilebiliyor — kalite
/// (Yunan harfleri, diyagram, tablo) LibreOffice'e çok yakın.
///
/// Kaynaklar (`render.html`, `pptx-preview.browser.js`) uygulama paketinde.
/// Servis tek bir `WKWebView`'i tekrar kullanır; dönüşümler sırayla yapılır
/// (aynı anda bir pptx), çağıran `await` ettiği için bu doğal olarak sağlanır.
@MainActor
@Observable
final class PptxConverter: NSObject {
    enum ConvertError: Error { case resourcesMissing, renderFailed, emptyDeck, pdfFailed, unreadable }

    private let webView: WKWebView
    private let bridge = Bridge()
    private var htmlLoaded = false

    override init() {
        webView = WKWebView(frame: .init(x: 0, y: 0, width: 1024, height: 768),
                            configuration: WKWebViewConfiguration())
        super.init()
        webView.navigationDelegate = bridge
        webView.configuration.userContentController.add(bridge, name: "spike")
    }

    /// Bir pptx'i PDF'e çevirir ve geçici bir dosyaya yazıp URL'ini döner.
    /// Çağıran PDF'i kalıcı yerine taşıdıktan sonra bu geçici dosyayı siler.
    func convert(pptx source: URL) async throws -> URL {
        try await ensureLoaded()

        // Dış (security-scoped) dosyayı oku.
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: source) else { throw ConvertError.unreadable }

        let slideCount = await render(data)
        guard slideCount > 0 else { throw ConvertError.emptyDeck }

        let pdfData = try await makePDF()
        let base = (source.lastPathComponent as NSString).deletingPathExtension
        let out = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(base)-\(UUID().uuidString.prefix(6)).pdf")
        do { try pdfData.write(to: out) } catch { throw ConvertError.pdfFailed }
        return out
    }

    // MARK: - Aşamalar

    private func ensureLoaded() async throws {
        if htmlLoaded { return }
        guard let html = Bundle.main.url(forResource: "render", withExtension: "html") else {
            throw ConvertError.resourcesMissing
        }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            // didFinish birden çok kez gelebilir; tek seferlik resume.
            var done = false
            bridge.onLoaded = {
                guard !done else { return }
                done = true
                cont.resume()
            }
            webView.loadFileURL(html, allowingReadAccessTo: html.deletingLastPathComponent())
        }
        htmlLoaded = true
    }

    private func render(_ data: Data) async -> Int {
        await withCheckedContinuation { (cont: CheckedContinuation<Int, Never>) in
            // DİKKAT: `window.renderBase64` bir Promise döndürür; evaluateJavaScript
            // bunu serileştiremeyip HATA ile döner — ama render aslında sürüyordur.
            // Gerçek bitiş `onRendered` köprüsünden gelir. Her iki geri-çağrı da
            // ana thread'de çalıştığı için basit bir bayrak tek-seferlik resume'u
            // garantiler (çift resume = fatal).
            var done = false
            func finish(_ n: Int) {
                guard !done else { return }
                done = true
                bridge.onRendered = { _ in }
                cont.resume(returning: n)
            }
            bridge.onRendered = { n in finish(n) }
            let b64 = data.base64EncodedString()
            let w = Int(webView.bounds.width > 0 ? webView.bounds.width : 1024)
            webView.evaluateJavaScript("window.renderBase64(\"\(b64)\", \(w));") { _, _ in
                // Promise sonucu hata gibi görünebilir — burada resume ETME;
                // gerçek bitişi onRendered verir. (Sadece onRendered hiç gelmezse
                // bu akış asılı kalmaz çünkü renderBase64 her durumda post eder.)
            }
        }
    }

    /// Her slaytı ayrı bir PDF sayfası olarak yakalar (slayt rect + createPDF),
    /// PDFKit ile birleştirip tek PDF'in verisini döner.
    private func makePDF() async throws -> Data {
        let rectsJS = """
        (function(){ var e = window.__spikeSlides ? window.__spikeSlides() : [];
          return e.map(function(r){return {x:r.x,y:r.y,w:r.w,h:r.h};}); })();
        """
        let rects: [[String: Any]] = await withCheckedContinuation { cont in
            webView.evaluateJavaScript(rectsJS) { result, _ in
                cont.resume(returning: (result as? [[String: Any]]) ?? [])
            }
        }
        guard !rects.isEmpty else { throw ConvertError.renderFailed }

        func num(_ v: Any?) -> CGFloat? {
            (v as? NSNumber).map { CGFloat(truncating: $0) }
        }

        let merged = PDFDocument()
        for r in rects {
            guard let x = num(r["x"]), let y = num(r["y"]),
                  let w = num(r["w"]), let h = num(r["h"]) else { continue }
            let cfg = WKPDFConfiguration()
            cfg.rect = CGRect(x: x, y: y, width: w, height: h)
            let pageData: Data? = await withCheckedContinuation { cont in
                webView.createPDF(configuration: cfg) { res in
                    if case .success(let d) = res { cont.resume(returning: d) }
                    else { cont.resume(returning: nil) }
                }
            }
            if let d = pageData, let doc = PDFDocument(data: d), let page = doc.page(at: 0) {
                merged.insert(page, at: merged.pageCount)
            }
        }
        guard merged.pageCount > 0, let data = merged.dataRepresentation() else {
            throw ConvertError.pdfFailed
        }
        return data
    }

    /// WKWebView delegeleri `@MainActor` dışı protokoller olduğu için ayrı,
    /// `@MainActor` olmayan küçük bir köprü nesnesinde tutuluyor.
    private final class Bridge: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var onLoaded: () -> Void = {}
        var onRendered: (Int) -> Void = { _ in }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            onLoaded()
        }

        func userContentController(_ uc: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any],
                  body["type"] as? String == "rendered" else { return }
            onRendered(body["slides"] as? Int ?? 0)
        }
    }
}
#endif
