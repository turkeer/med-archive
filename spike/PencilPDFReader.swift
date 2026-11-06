import SwiftUI
import UIKit
import PDFKit
import PencilKit

/// Okuyucuyu dışarıdan süren düğmeler (sayfa çevirme). Finger-scroll/zoom bu
/// spike'ta yok — resmi overlay API'si (PDFPageOverlayViewProvider) bu ortamda
/// tetiklenmediğinden, eşzamanlı "parmak gez + kalem yaz"ı Faz 5'e bıraktık.
/// Burada sayfa çevirme açık düğmelerle; kalem her zaman çizer.
final class ReaderController: ObservableObject {
    weak var coordinator: PencilPDFReader.Coordinator?
    func next() { coordinator?.next() }
    func prev() { coordinator?.prev() }
}

/// Spike okuyucu — **çalışan, doğru hizalanan** sürüm.
///
/// Tek-sayfa modunda sayfa ekranı doldurur (içeride kaydırma yok), üstüne tam
/// boyut bir `PKCanvasView` gelir. Böylece kalem sayfaya hizalı çizer ve her
/// sayfanın çizimi diske kaydedilip geri yüklenir. Sayfalar ◀▶ ile çevrilir.
struct PencilPDFReader: UIViewRepresentable {
    let url: URL
    let controller: ReaderController
    var onStatus: (String) -> Void = { _ in }

    func makeCoordinator() -> Coordinator { Coordinator(url: url) }

    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        let coord = context.coordinator

        // Altta PDF — tek sayfa, ekranı doldurur.
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePage
        pdfView.displayDirection = .horizontal
        pdfView.backgroundColor = .systemGray5
        pdfView.translatesAutoresizingMaskIntoConstraints = false
        let doc = PDFDocument(url: url)
            ?? (try? Data(contentsOf: url)).flatMap { PDFDocument(data: $0) }
        pdfView.document = doc
        container.addSubview(pdfView)

        // Üstte kalem tuvali — tam boyut, sayfaya denk gelir.
        let canvas = PKCanvasView()
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.drawingPolicy = .pencilOnly
        canvas.tool = PKInkingTool(.pen, color: .systemBlue, width: 6)
        canvas.delegate = coord
        canvas.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(canvas)

        NSLayoutConstraint.activate([
            pdfView.topAnchor.constraint(equalTo: container.topAnchor),
            pdfView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            pdfView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            pdfView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            canvas.topAnchor.constraint(equalTo: container.topAnchor),
            canvas.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            canvas.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            canvas.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])

        coord.pdfView = pdfView
        coord.canvas = canvas
        coord.onStatus = onStatus
        controller.coordinator = coord
        coord.loadCurrentPageDrawing()

        DispatchQueue.main.async { [weak canvas] in
            guard let canvas else { return }
            coord.toolPicker.setVisible(true, forFirstResponder: canvas)
            coord.toolPicker.addObserver(canvas)
            canvas.becomeFirstResponder()
        }

        coord.reportStatus(doc == nil ? "PDF YÜKLENEMEDİ" : "Yüklendi: \(doc!.pageCount) sayfa")
        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {}

    // MARK: - Coordinator

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        let url: URL
        weak var pdfView: PDFView?
        weak var canvas: PKCanvasView?
        var onStatus: ((String) -> Void)?
        let toolPicker = PKToolPicker()

        init(url: URL) {
            self.url = url
            super.init()
            try? FileManager.default.createDirectory(
                at: Self.dir(url), withIntermediateDirectories: true
            )
        }

        private var currentIndex: Int {
            guard let pv = pdfView, let page = pv.currentPage else { return 0 }
            return pv.document?.index(for: page) ?? 0
        }

        func next() {
            saveCurrent()
            pdfView?.goToNextPage(nil)
            loadCurrentPageDrawing()
            reportStatus(nil)
        }

        func prev() {
            saveCurrent()
            pdfView?.goToPreviousPage(nil)
            loadCurrentPageDrawing()
            reportStatus(nil)
        }

        func saveCurrent() {
            guard let canvas else { return }
            save(canvas.drawing, currentIndex)
        }

        func loadCurrentPageDrawing() {
            canvas?.drawing = load(currentIndex)
        }

        func canvasViewDrawingDidChange(_ cv: PKCanvasView) {
            save(cv.drawing, currentIndex)
        }

        private var pageCount: Int { pdfView?.document?.pageCount ?? 0 }

        func reportStatus(_ base: String?) {
            let text = (base ?? "Sayfa \(currentIndex + 1)/\(pageCount)") + " · kalemle yaz, ◀▶ ile sayfa"
            DispatchQueue.main.async { self.onStatus?(text) }
        }

        // MARK: Kalıcılık — her sayfa bir .drawing dosyası
        private static func dir(_ url: URL) -> URL {
            URL.documentsDirectory
                .appending(path: "Drawings", directoryHint: .isDirectory)
                .appending(path: url.deletingPathExtension().lastPathComponent, directoryHint: .isDirectory)
        }
        private func fileURL(_ i: Int) -> URL { Self.dir(url).appending(path: "\(i).drawing") }
        private func load(_ i: Int) -> PKDrawing {
            (try? Data(contentsOf: fileURL(i))).flatMap { try? PKDrawing(data: $0) } ?? PKDrawing()
        }
        private func save(_ d: PKDrawing, _ i: Int) {
            try? d.dataRepresentation().write(to: fileURL(i))
        }
    }
}
