import Foundation

/// Quoting text from the conversation, as the official web does (`dsh-message-quotes`): a quote is
/// sent as an ordinary Markdown blockquote and nothing else. A message carries no quote field;
/// a sent message shows its quotes by recognizing explicitly marked blockquote lines, so a
/// hand-written `> …` shows the same way.
enum MessageQuotes {
    /// One `> `-prefixed line per line of the selected text (`formatQuoteText`).
    static func format(_ text: String) -> String {
        normalized(text).split(separator: "\n", omittingEmptySubsequences: false).map { "> \($0)" }.joined(separator: "\n")
    }

    /// The selected text back from consecutive blockquote lines: one marker off each (`quoteTextOf`).
    static func decode(_ text: String) -> String {
        normalized(text).replacing(#/(?m)^ {0,3}>[ \t]?/#, with: "")
    }

    /// Consecutive lines marked `>` (up to three leading spaces), whose text is not blank
    /// (`messageQuoteRanges`). No lazy continuation and no code fences, as upstream.
    static func ranges(in text: String) -> [Range<String.Index>] {
        text.matches(of: #/(?m)^ {0,3}>[^\r\n]*(?:\r?\n {0,3}>[^\r\n]*)*/#)
            .map(\.range)
            .filter { !decode(String(text[$0])).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    /// The draft as the model reads it. The quotes come first, in the order they were added, each a
    /// blockquote; quotes and text are set apart by a blank line (`serializeDraftPrompt`).
    static func compose(quotes: [String], text: String) -> String {
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return (quotes.map(format) + (body.isEmpty ? [] : [body])).joined(separator: "\n\n")
    }

    enum Segment: Hashable {
        case text(String)
        case quote(String)
    }

    /// A sent message in display order. The blank line that sets a quote apart from what follows
    /// is not shown (the web shows it as a space in its inline layout).
    static func segments(_ text: String) -> [Segment] {
        let found = ranges(in: text)
        guard !found.isEmpty else { return [.text(text)] }
        var segments: [Segment] = []
        var cursor = text.startIndex
        func addText(_ upTo: String.Index) {
            let piece = String(text[cursor..<upTo]).trimmingCharacters(in: .newlines)
            if !piece.isEmpty { segments.append(.text(piece)) }
        }
        for range in found {
            addText(range.lowerBound)
            segments.append(.quote(decode(String(text[range]))))
            cursor = range.upperBound
        }
        addText(text.endIndex)
        return segments
    }

    /// One line for a list row (the queue): quotes as 「…」, whitespace folded.
    static func preview(_ text: String) -> String {
        segments(text).map { segment in
            switch segment {
            case .text(let text): text
            case .quote(let quote): "「\(quote)」"
            }
        }
        .joined(separator: " ")
        .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private static func normalized(_ text: String) -> String {
        text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
    }
}

/// The composer's quotes in the web's draft store (`dsh.conversation.<sid>`): the stored text holds
/// each quote as its blockquote, `{offset, length, text}` saying where (UTF-16, as the web counts).
/// The quotes lead the stored text, each followed by a space, as quote nodes in the web's editor are.
enum DraftQuotes {
    static func store(quotes: [String], text: String) -> (text: String, quotes: [JSON]) {
        var stored = ""
        var spans: [JSON] = []
        for quote in quotes {
            let formatted = MessageQuotes.format(quote)
            spans.append(["offset": .number(Double(stored.utf16.count)), "length": .number(Double(formatted.utf16.count)), "text": .string(quote)])
            stored += formatted + " "
        }
        return (stored + text, spans)
    }

    /// The quotes back out of a stored draft, and the text without them. Spans that do not hold
    /// their blockquote are dropped and their text stays as it is.
    static func restore(text: String, quotes spans: [JSON]) -> (quotes: [String], text: String) {
        var utf16 = Array(text.utf16)
        var quotes: [(offset: Int, text: String)] = []
        for span in spans {
            guard let offset = span["offset"].int, let length = span["length"].int, let quote = span["text"].string,
                  !quote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  offset >= 0, length > 0, offset + length <= utf16.count,
                  String(decoding: utf16[offset..<offset + length], as: UTF16.self) == MessageQuotes.format(quote) else { continue }
            quotes.append((offset, quote))
        }
        quotes.sort { $0.offset < $1.offset }
        // Back to front, so the earlier offsets stay good; each takes the space after it along.
        for quote in quotes.reversed() {
            let end = quote.offset + MessageQuotes.format(quote.text).utf16.count
            let through = end < utf16.count && utf16[end] == UInt16(UInt8(ascii: " ")) ? end + 1 : end
            utf16.removeSubrange(quote.offset..<through)
        }
        return (quotes.map(\.text), String(decoding: utf16, as: UTF16.self))
    }
}
