import Foundation

struct LegalDocumentStore {
    let bundle: Bundle

    init(bundle: Bundle = .main) {
        self.bundle = bundle
    }

    func load(_ document: LegalDocument) throws -> LegalDocumentBody {
        let candidates = [
            bundle.url(
                forResource: document.resourceName,
                withExtension: "txt",
                subdirectory: "Legal"
            ),
            bundle.url(
                forResource: document.resourceName,
                withExtension: "txt"
            ),
        ].compactMap { $0 }

        guard let url = candidates.first else {
            throw LegalDocumentError.missingResource(document.resourceName)
        }
        let text = try String(contentsOf: url, encoding: .utf8)
        let body = LegalDocumentBody(text: text)
        guard !body.blocks.isEmpty else {
            throw LegalDocumentError.emptyResource(document.resourceName)
        }
        return body
    }
}

extension LegalDocument {
    func load(in bundle: Bundle = .main) throws -> LegalDocumentBody {
        try LegalDocumentStore(bundle: bundle).load(self)
    }
}
