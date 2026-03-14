import SwiftUI
import WebKit

/// 수학 공식(LaTeX)을 포함한 마크다운을 렌더링하는 WKWebView 기반 컴포넌트.
/// KaTeX로 수학 공식, marked.js로 마크다운을 처리한다.
struct MathMarkdownView: NSViewRepresentable {
    let content: String

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        guard !content.isEmpty else {
            if !context.coordinator.lastContent.isEmpty {
                webView.loadHTMLString("", baseURL: nil)
                context.coordinator.lastContent = ""
            }
            return
        }
        guard context.coordinator.lastContent != content else { return }
        context.coordinator.lastContent = content
        webView.loadHTMLString(Self.buildHTML(content), baseURL: nil)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }
    class Coordinator { var lastContent = "" }

    static func buildHTML(_ content: String) -> String {
        let b64 = Data(content.utf8).base64EncodedString()
        return #"""
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/katex@0.16.11/dist/katex.min.css">
<style>
@media (prefers-color-scheme: light) {
  :root {
    --fg: #24292f; --fg2: #57606a; --fg3: #8b949e;
    --bg-code: #f6f8fa; --border: #d0d7de; --link: #0969da;
  }
}
@media (prefers-color-scheme: dark) {
  :root {
    --fg: #c9d1d9; --fg2: #8b949e; --fg3: #6e7681;
    --bg-code: #161b22; --border: #30363d; --link: #58a6ff;
  }
}
* { box-sizing: border-box; }
body {
  font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Helvetica, Arial, sans-serif;
  font-size: 14px; line-height: 1.6; color: var(--fg);
  background: transparent; padding: 16px; margin: 0; word-wrap: break-word;
}
h1, h2, h3, h4, h5, h6 {
  margin-top: 24px; margin-bottom: 16px; font-weight: 600; line-height: 1.25;
}
h1 { font-size: 1.7em; border-bottom: 1px solid var(--border); padding-bottom: .3em; }
h2 { font-size: 1.4em; border-bottom: 1px solid var(--border); padding-bottom: .3em; }
h3 { font-size: 1.17em; }
h4 { font-size: 1em; }
p { margin: 0 0 16px; }
code {
  background: var(--bg-code); padding: .2em .4em; border-radius: 6px;
  font-size: 85%; font-family: "SF Mono", Menlo, Consolas, monospace;
}
pre {
  background: var(--bg-code); padding: 16px; border-radius: 6px;
  overflow-x: auto; margin: 0 0 16px;
}
pre code { background: none; padding: 0; font-size: 100%; }
blockquote {
  border-left: .25em solid var(--border); padding: 0 1em;
  color: var(--fg2); margin: 0 0 16px;
}
table { border-collapse: collapse; width: 100%; margin: 16px 0; }
th, td { border: 1px solid var(--border); padding: 6px 13px; }
th { background: var(--bg-code); font-weight: 600; }
tr:nth-child(even) { background: var(--bg-code); }
a { color: var(--link); text-decoration: none; }
a:hover { text-decoration: underline; }
ul, ol { padding-left: 2em; margin: 0 0 16px; }
li + li { margin-top: .25em; }
li > ul, li > ol { margin-bottom: 0; }
img { max-width: 100%; }
hr { border: none; border-top: 1px solid var(--border); margin: 24px 0; }
strong { font-weight: 600; }
.katex-display { overflow-x: auto; overflow-y: hidden; padding: 8px 0; }
.katex { font-size: 1.1em; }
</style>
</head>
<body>
<div id="content"></div>
<script src="https://cdn.jsdelivr.net/npm/katex@0.16.11/dist/katex.min.js"></script>
<script src="https://cdn.jsdelivr.net/npm/katex@0.16.11/dist/contrib/auto-render.min.js"></script>
<script src="https://cdn.jsdelivr.net/npm/marked/marked.min.js"></script>
<script>
(function() {
  var raw;
  try {
    raw = new TextDecoder().decode(
      Uint8Array.from(atob('\#(b64)'), function(c) { return c.charCodeAt(0); })
    );
  } catch(e) { raw = ''; }

  // 수학 블록을 marked 처리 전에 보호 (underscore 등이 깨지지 않도록)
  var mathBlocks = [];
  var MP = 'MPROTECT_', ME = '_MEND';

  function protect(t) {
    // display math: $$...$$
    t = t.replace(/\$\$([\s\S]*?)\$\$/g, function(m) {
      mathBlocks.push(m); return MP + (mathBlocks.length - 1) + ME;
    });
    // inline math: $...$
    t = t.replace(/\$([^\$\n]+?)\$/g, function(m) {
      mathBlocks.push(m); return MP + (mathBlocks.length - 1) + ME;
    });
    // \(...\) inline
    t = t.replace(/\\\([\s\S]*?\\\)/g, function(m) {
      mathBlocks.push(m); return MP + (mathBlocks.length - 1) + ME;
    });
    // \[...\] display
    t = t.replace(/\\\[[\s\S]*?\\\]/g, function(m) {
      mathBlocks.push(m); return MP + (mathBlocks.length - 1) + ME;
    });
    return t;
  }

  function restore(h) {
    for (var i = 0; i < mathBlocks.length; i++) {
      h = h.split(MP + i + ME).join(mathBlocks[i]);
    }
    return h;
  }

  var el = document.getElementById('content');

  if (typeof marked !== 'undefined') {
    el.innerHTML = restore(marked.parse(protect(raw)));
  } else {
    el.innerText = raw;
  }

  try {
    if (typeof renderMathInElement !== 'undefined') {
      renderMathInElement(el, {
        delimiters: [
          {left: '$$', right: '$$', display: true},
          {left: '$', right: '$', display: false},
          {left: '\\(', right: '\\)', display: false},
          {left: '\\[', right: '\\]', display: true}
        ],
        throwOnError: false
      });
    }
  } catch(e) {}
})();
</script>
</body>
</html>
"""#
    }
}
