import Social
import UniformTypeIdentifiers

final class ShareViewController: SLComposeServiceViewController {
    override func isContentValid() -> Bool {
        !(contentText ?? "").isEmpty && (contentText ?? "").utf8.count <= 20_000
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Earnline"
        navigationController?.navigationBar.topItem?.rightBarButtonItem?.title = NSLocalizedString("Save", comment: "")
        guard (contentText ?? "").isEmpty,
              let item = extensionContext?.inputItems.first as? NSExtensionItem,
              let provider = item.attachments?.first(where: {
                  $0.hasItemConformingToTypeIdentifier(UTType.plainText.identifier)
              }) else { return }
        provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) { [weak self] value, _ in
            let text = value as? String
            Task { @MainActor in
                if let text { self?.textView.text = text; self?.validateContent() }
            }
        }
    }

    override func didSelectPost() {
        guard let text = contentText, isContentValid(), let directory = LedgerWidgetSnapshot.directory else {
            showError()
            return
        }
        do {
            let inbox = directory.appendingPathComponent("share-inbox", isDirectory: true)
            try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
            try Data(text.utf8).write(to: inbox.appendingPathComponent(UUID().uuidString + ".txt"),
                                      options: [.atomic, .completeFileProtection])
            extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
        } catch { showError() }
    }

    private func showError() {
        let alert = UIAlertController(title: NSLocalizedString("Could not save shared text", comment: ""),
                                      message: NSLocalizedString("Open Earnline and paste the text into Paste lines.", comment: ""),
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}
