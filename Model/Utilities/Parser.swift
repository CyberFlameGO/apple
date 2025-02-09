//
//  Parser.swift
//  Kiwix
//
//  Created by Chris Li on 1/1/20.
//  Copyright © 2020 Chris Li. All rights reserved.
//

import CoreLocation
import NaturalLanguage
import UIKit

import Fuzi

class Parser {
    private let document: HTMLDocument
    
    static private let boldFont = UIFont.systemFont(ofSize: 12.0, weight: .medium)
    
    init(document: HTMLDocument) {
        self.document = document
    }
    
    convenience init(html: String) throws {
        self.init(document: try HTMLDocument(string: html))
    }
    
    convenience init(data: Data) throws {
        self.init(document: try HTMLDocument(data: data))
    }
    
    convenience init(url: URL) throws {
        guard let content = ZimFileService.shared.getURLContent(url: url) else { throw NSError() }
        try self.init(data: content.data)
    }
    
    var title: String? { document.title }
    
    func getFirstParagraph() -> NSAttributedString? {
        guard let firstParagraph = document.firstChild(xpath: "//p") else { return nil }
        let snippet = NSMutableAttributedString()
        for child in firstParagraph.childNodes(ofTypes: [.Text, .Element]) {
            if let element = child as? Fuzi.XMLElement, element.attributes["class"]?.contains("mw-ref") == true {
                continue
            } else if let element = child as? Fuzi.XMLElement {
                let attributedSting = NSAttributedString(
                    string: element.stringValue.replacingOccurrences(of: "\n", with: ""),
                    attributes: element.tag == "b" ? [.font: Parser.boldFont] : nil
                )
                snippet.append(attributedSting)
            } else {
                let text = child.stringValue.replacingOccurrences(of: "\n", with: "")
                snippet.append(NSAttributedString(string: text))
            }
        }
        return snippet.length > 0 ? snippet : nil
    }
    
    func getFirstSentence(languageCode: String?) -> NSAttributedString? {
        guard let firstParagraph = self.getFirstParagraph() else { return nil }
        let text = firstParagraph.string
        var firstSentence: NSAttributedString?
        
        let tokenizer = NLTokenizer(unit: .sentence)
        if let languageCode = languageCode {tokenizer.setLanguage(NLLanguage(languageCode))}
        tokenizer.string = text
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            firstSentence = firstParagraph.attributedSubstring(from: NSRange(range, in: firstParagraph.string))
            return false
        }
        return firstSentence
    }
    
    func getFirstImagePath() -> String? {
        guard let firstImage = document.firstChild(xpath: "//img") else { return nil }
        return firstImage.attributes["src"]
    }
    
    func getOutlineItems() -> [OutlineItem] {
        document.css("h1, h2, h3, h4, h5, h6").enumerated().compactMap { index, element in
            guard let tag = element.tag, let level = Int(tag.suffix(1)) else { return nil }
            let text = element.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            return OutlineItem(index: index, text: text, level: level)
        }
    }
    
    func getHierarchicalOutlineItems() -> [OutlineItem] {
        let root = OutlineItem(index: -1, text: "", level: 0)
        var stack: [OutlineItem] = [root]
        
        document.css("h1, h2, h3, h4, h5, h6").enumerated().forEach { index, element in
            guard let tag = element.tag, let level = Int(tag.suffix(1)) else { return }
            let text = element.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            let item = OutlineItem(index: index, text: text, level: level)
            
            // get last item in stack
            // if last item is child of item's sibling, unwind stack until a sibling is found
            guard var lastItem = stack.last else { return }
            while lastItem.level > item.level {
                stack.removeLast()
                lastItem = stack[stack.count - 1]
            }
            
            // if item is last item's sibling, add item to parent and replace last item with itself in stack
            // if item is last item's child, add item to parent and add item to stack
            if lastItem.level == item.level {
                stack[stack.count - 2].addChild(item)
                stack[stack.count - 1] = item
            } else if lastItem.level < item.level {
                stack[stack.count - 1].addChild(item)
                stack.append(item)
            }
        }
        
        // if there is only one h1, flatten one level
        if let rootChildren = root.children, rootChildren.count == 1, let rootFirstChild = rootChildren.first {
            let firstItem = OutlineItem(index: rootFirstChild.index, text: rootFirstChild.text, level: rootFirstChild.level)
            return [firstItem] + (rootFirstChild.children ?? [])
        } else {
            return root.children ?? []
        }
    }
    
//    func getGeoCoordinate() -> CLLocationCoordinate2D? {
//        do {
//            let elements = try document.select("head > meta[name='geo.position']")
//            let content = try elements.first()?.attr("content")
//            guard let parts = content?.split(separator: ";"), parts.count == 2,
//                let lat = Double(parts[0]), let lon = Double(parts[1]) else { return nil }
//            return CLLocationCoordinate2D(latitude: lat, longitude: lon)
//        } catch { return nil }
//    }
    
    class func parseBodyFragment(_ bodyFragment: String) -> NSAttributedString? {
        let html = "<!DOCTYPE html><html><head></head><body><p>\(bodyFragment)</p></body></html>"
        return (try? Parser(html: html))?.getFirstParagraph()
    }
}
