// WebPage — find-in-page highlight engine for WebPageController.

import Foundation
import os
import WebKit

// MARK: - Find in Page

struct FindResponse: Decodable, Sendable {
    var total: Int
    var index: Int
}

extension WebPageController {
    static let findHighlighterScript = """
    (function() {
      if (window.__outerviewFindInstalled) return;
      window.__outerviewFindInstalled = true;
      window.__outerviewFindMatches = 0;
      window.__outerviewFindIndex = 0;
      function clearMarks() {
        var prev = document.querySelectorAll('.outerview-find-highlight');
        for (var p = 0; p < prev.length; p++) {
          var el = prev[p];
          var parent = el.parentNode;
          if (!parent) { continue; }
          parent.replaceChild(document.createTextNode(el.textContent), el);
          parent.normalize();
        }
        window.__outerviewFindMatches = 0;
        window.__outerviewFindIndex = 0;
      }
      function paintCurrent() {
        var marks = document.querySelectorAll('.outerview-find-highlight');
        for (var i = 0; i < marks.length; i++) {
          var m = marks[i];
          if (i === window.__outerviewFindIndex - 1) {
            m.style.backgroundColor = '#FF9800';
            m.style.color = '#000';
            if (m.scrollIntoView) { m.scrollIntoView({block:'center'}); }
          } else {
            m.style.backgroundColor = '#FFEB3B';
            m.style.color = '#000';
          }
        }
      }
      window.__outerviewFind = function(query) {
        clearMarks();
        var q = String(query || '');
        if (!q) { return JSON.stringify({total:0,index:0}); }
        var lower = q.toLowerCase();
        if (!lower || !document.body) { return JSON.stringify({total:0,index:0}); }
        var walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT, null);
        var nodes = [];
        while (walker.nextNode()) { nodes.push(walker.currentNode); }
        var count = 0;
        for (var i = 0; i < nodes.length; i++) {
          var node = nodes[i];
          var text = node.nodeValue;
          if (!text) { continue; }
          var tag = node.parentNode && node.parentNode.tagName;
          if (tag === 'SCRIPT' || tag === 'STYLE' || tag === 'NOSCRIPT') { continue; }
          if (text.toLowerCase().indexOf(lower) === -1) { continue; }
          var frag = document.createDocumentFragment();
          var remaining = text;
          var lowerRemaining = remaining.toLowerCase();
          var matched = false;
          while (true) {
            var j = lowerRemaining.indexOf(lower);
            if (j === -1) {
              frag.appendChild(document.createTextNode(remaining));
              break;
            }
            matched = true;
            frag.appendChild(document.createTextNode(remaining.slice(0, j)));
            var mark = document.createElement('mark');
            mark.className = 'outerview-find-highlight';
            mark.style.backgroundColor = '#FFEB3B';
            mark.style.color = '#000';
            mark.textContent = remaining.substr(j, q.length);
            frag.appendChild(mark);
            count++;
            remaining = remaining.slice(j + q.length);
            lowerRemaining = remaining.toLowerCase();
            if (!remaining) { break; }
          }
          if (matched) { node.parentNode.replaceChild(frag, node); }
        }
        window.__outerviewFindMatches = count;
        window.__outerviewFindIndex = count > 0 ? 1 : 0;
        paintCurrent();
        return JSON.stringify({total:count,index:window.__outerviewFindIndex});
      };
      window.__outerviewStep = function(delta) {
        var total = window.__outerviewFindMatches || 0;
        if (total === 0) { return JSON.stringify({total:0,index:0}); }
        var d = Number(delta) || 0;
        var idx = window.__outerviewFindIndex || 1;
        idx = ((idx - 1 + d) % total + total) % total + 1;
        window.__outerviewFindIndex = idx;
        paintCurrent();
        return JSON.stringify({total:total,index:idx});
      };
      window.__outerviewClear = function() { clearMarks(); };
    })();
    """

    nonisolated static func parsedFindCounts(from jsonString: String?) -> (total: Int, index: Int) {
        guard let jsonString,
              let data = jsonString.data(using: .utf8)
        else {
            return (0, 0)
        }
        let decoded: FindResponse
        do {
            decoded = try JSONDecoder().decode(FindResponse.self, from: data)
        } catch {
            return (0, 0)
        }
        return (max(0, decoded.total), max(0, decoded.index))
    }

    nonisolated static func parsedFindTotal(from jsonString: String?) -> Int {
        parsedFindCounts(from: jsonString).total
    }

    nonisolated static func parsedFindIndex(from jsonString: String?) -> Int {
        parsedFindCounts(from: jsonString).index
    }

    nonisolated static func escapedFindQuery(_ query: String) -> String {
        query
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
    }

    func findText(_ query: String) async -> Int {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            await clearFind()
            return 0
        }
        let escaped = Self.escapedFindQuery(trimmed)
        do {
            let result = try await webView.evaluateJavaScript("window.__outerviewFind('\(escaped)')")
            guard let json = result as? String else { return 0 }
            return Self.parsedFindTotal(from: json)
        } catch {
            Logger(subsystem: "com.volcrypt.OuterView", category: "WebPage")
                .error("findText failed: \(error.localizedDescription, privacy: .public)")
            return 0
        }
    }

    func findStep(_ delta: Int) async -> Int {
        do {
            let result = try await webView.evaluateJavaScript("window.__outerviewStep(\(delta))")
            if let json = result as? String {
                return Self.parsedFindIndex(from: json)
            }
            if let number = result as? Int {
                return max(0, number)
            }
            if let number = result as? Double {
                return max(0, Int(number))
            }
            return 0
        } catch {
            Logger(subsystem: "com.volcrypt.OuterView", category: "WebPage")
                .error("findStep failed: \(error.localizedDescription, privacy: .public)")
            return 0
        }
    }

    func clearFind() async {
        do {
            _ = try await webView.evaluateJavaScript("window.__outerviewClear && window.__outerviewClear()")
        } catch {
            Logger(subsystem: "com.volcrypt.OuterView", category: "WebPage")
                .error("clearFind failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
