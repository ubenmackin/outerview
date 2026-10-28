//
//  ReaderMode.swift
//  OuterView
//

import Foundation
import UIKit

/// Reader color scheme. The raw value is what persists under "readerTheme".
enum ReaderTheme: String, CaseIterable, Sendable {
    case light
    case sepia
    case dark

    var backgroundHex: String {
        switch self {
        case .light:
            "#FFFFFF"
        case .sepia:
            "#F4ECD8"
        case .dark:
            "#1A1A1A"
        }
    }

    var foregroundHex: String {
        switch self {
        case .light:
            "#111111"
        case .sepia:
            "#433422"
        case .dark:
            "#F5F5F5"
        }
    }

    var backgroundColor: UIColor {
        switch self {
        case .light:
            UIColor(red: 1, green: 1, blue: 1, alpha: 1)
        case .sepia:
            UIColor(red: 244 / 255, green: 236 / 255, blue: 216 / 255, alpha: 1)
        case .dark:
            UIColor(red: 26 / 255, green: 26 / 255, blue: 26 / 255, alpha: 1)
        }
    }

    var foregroundColor: UIColor {
        switch self {
        case .light:
            UIColor(red: 17 / 255, green: 17 / 255, blue: 17 / 255, alpha: 1)
        case .sepia:
            UIColor(red: 67 / 255, green: 52 / 255, blue: 34 / 255, alpha: 1)
        case .dark:
            UIColor(red: 245 / 255, green: 245 / 255, blue: 245 / 255, alpha: 1)
        }
    }
}

/// Decoded extraction payload: plain-text title/byline plus pre-sanitized
/// body HTML holding paragraphs and images only.
struct ReaderArticle: Decodable, Equatable, Sendable {
    var title: String
    var byline: String?
    var html: String
}

/// Pure reader engine: extraction styling, readability decisions, and
/// preference storage. WebPageController only executes the scripts.
enum ReaderMode: Sendable {
    static let themeDefaultsKey = "readerTheme"
    static let fontSizeDefaultsKey = "readerFontSize"
    static let defaultFontSize = 20
    static let minimumFontSize = 14
    static let maximumFontSize = 28
    static let minimumReadableCharacters = 200
    static let minimumParagraphCharacters = 60

    static func clampedFontSize(_ size: Int) -> Int {
        min(max(size, minimumFontSize), maximumFontSize)
    }

    static func storedTheme(defaults: UserDefaults = .standard) -> ReaderTheme {
        guard let raw = defaults.string(forKey: themeDefaultsKey),
              let theme = ReaderTheme(rawValue: raw)
        else {
            return .light
        }
        return theme
    }

    static func storedFontSize(defaults: UserDefaults = .standard) -> Int {
        let stored = defaults.integer(forKey: fontSizeDefaultsKey)
        guard stored != 0 else {
            return defaultFontSize
        }
        return clampedFontSize(stored)
    }

    static func persist(theme: ReaderTheme, defaults: UserDefaults = .standard) {
        defaults.set(theme.rawValue, forKey: themeDefaultsKey)
    }

    static func persist(fontSize: Int, defaults: UserDefaults = .standard) {
        defaults.set(clampedFontSize(fontSize), forKey: fontSizeDefaultsKey)
    }

    /// Decodes the extraction payload. Short or malformed payloads are not
    /// readerable and yield nil.
    static func parsedArticle(from jsonString: String?) -> ReaderArticle? {
        guard let jsonString,
              !jsonString.isEmpty,
              let data = jsonString.data(using: .utf8)
        else {
            return nil
        }
        let article: ReaderArticle
        do {
            article = try JSONDecoder().decode(ReaderArticle.self, from: data)
        } catch {
            return nil
        }
        let total = article.title.count + strippedText(article.html).count
        guard total >= minimumReadableCharacters else {
            return nil
        }
        return article
    }

    /// Derives a preview snippet from the canonical extraction payload, so
    /// previews reuse the single reader engine instead of a second script.
    static func previewSnippet(from jsonString: String?, maxCount: Int = 2, maxLength: Int = 300) -> String? {
        guard let jsonString,
              !jsonString.isEmpty,
              let data = jsonString.data(using: .utf8)
        else {
            return nil
        }
        let article: ReaderArticle
        do {
            article = try JSONDecoder().decode(ReaderArticle.self, from: data)
        } catch {
            return nil
        }
        let text = strippedText(article.html)
        guard !text.isEmpty else { return nil }
        let snippet = SentenceExtractor.firstSentences(from: text, maxCount: maxCount, maxLength: maxLength)
        return snippet.isEmpty ? nil : snippet
    }

    /// Extracts the article and caches it on window.__outerviewReader. Returns
    /// sanitized JSON, or null when the page is not readerable.
    static func extractionScript() -> String {
        """
        (function() {
          if (!window.__outerviewReader) { window.__outerviewReader = {}; }
          var reader = window.__outerviewReader;
          function trimmedText(node) {
            var value = node && node.textContent ? node.textContent : '';
            return value.replace(/^\\s+|\\s+$/g, '');
          }
          function escapeHtml(value) {
            return String(value).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
          }
          function escapeAttr(value) {
            return escapeHtml(value).replace(/"/g, '&quot;');
          }
          var skipSelector = 'nav,aside,header,footer,script,style,noscript,form,.ad,.ads,.advertisement,.sidebar,.menu,.nav,.comment,.comments';
          function isSkipped(element) {
            if (!element || !element.closest) { return true; }
            try {
              return element.closest(skipSelector) !== null;
            } catch (ignored) {
              return false;
            }
          }
          var rawTitle = document.title ? document.title : '';
          var title = rawTitle.replace(/^\\s+|\\s+$/g, '');
          var heading = document.querySelector('article h1, main h1, h1');
          var headingText = trimmedText(heading);
          if (headingText.length > title.length) { title = headingText; }
          var byline = null;
          var authorMeta = document.querySelector('meta[name="author"]');
          var authorContent = authorMeta ? authorMeta.getAttribute('content') : null;
          if (authorContent && authorContent.replace(/^\\s+|\\s+$/g, '') !== '') {
            byline = authorContent.replace(/^\\s+|\\s+$/g, '').slice(0, 140);
          }
          if (!byline) {
            var bylineEl = document.querySelector('[rel="author"], .byline, .author');
            var bylineText = trimmedText(bylineEl);
            if (bylineText !== '') { byline = bylineText.slice(0, 140); }
          }
          var candidates = document.querySelectorAll('p, img');
          var parts = [];
          var total = 0;
          for (var i = 0; i < candidates.length; i++) {
            var el = candidates[i];
            if (isSkipped(el)) { continue; }
            if (el.tagName === 'P') {
              var paragraph = trimmedText(el);
              if (paragraph.length < 60) { continue; }
              parts.push('<p>' + escapeHtml(paragraph) + '</p>');
              total += paragraph.length;
            } else if (el.tagName === 'IMG') {
              var source = el.currentSrc || el.src || '';
              if (!source) { continue; }
              var alt = el.getAttribute ? (el.getAttribute('alt') || '') : '';
              parts.push('<img src="' + escapeAttr(source) + '" alt="' + escapeAttr(alt) + '">');
            }
          }
          if (total < 200) {
            reader.article = null;
            return null;
          }
          var article = { title: title, byline: byline, html: parts.join('') };
          reader.article = article;
          return JSON.stringify(article);
        })();
        """
    }

    /// Re-renders the cached article with the theme inline. Image sources stay
    /// absolute, so they keep loading without a reload.
    static func replaceBodyScript(theme: ReaderTheme, fontSize: Int) -> String {
        let size = clampedFontSize(fontSize)
        return """
        (function() {
          var reader = window.__outerviewReader;
          if (!reader || !reader.article) { return; }
          function escapeHtml(value) {
            return String(value == null ? '' : value).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
          }
          var title = escapeHtml(reader.article.title || '');
          var byline = reader.article.byline
            ? '<p class="outerview-byline">' + escapeHtml(reader.article.byline) + '</p>'
            : '';
          document.body.setAttribute('style', 'margin:0;background:\(theme.backgroundHex);color:\(theme.foregroundHex);');
          document.body.innerHTML = '<main class="outerview-reader" style="max-width:42em;margin:0 auto;padding:24px 20px 64px;'
            + 'font-family:-apple-system,Georgia,serif;font-size:\(size)px;line-height:1.7;'
            + 'color:\(theme.foregroundHex);background:\(theme.backgroundHex);">'
            + '<h1 style="font-size:1.5em;line-height:1.25;margin:0 0 8px;">' + title + '</h1>'
            + byline
            + (reader.article.html || '')
            + '</main>';
          var images = document.body.querySelectorAll('.outerview-reader img');
          for (var i = 0; i < images.length; i++) {
            images[i].setAttribute('style', 'max-width:100%;height:auto;display:block;margin:16px 0;');
          }
          var paragraphs = document.body.querySelectorAll('.outerview-reader p');
          for (var j = 0; j < paragraphs.length; j++) {
            if (paragraphs[j].className === 'outerview-byline') {
              paragraphs[j].setAttribute('style', 'opacity:0.7;margin:0 0 16px;font-size:0.85em;');
            } else {
              paragraphs[j].setAttribute('style', 'margin:0 0 1em;');
            }
          }
        })();
        """
    }

    private static func strippedText(_ html: String) -> String {
        html.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
