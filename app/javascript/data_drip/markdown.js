// Minimal markdown-subset renderer for backfill instructions.
//
// Supports: `#`/`##`/`###` headers, `**bold**`, `` `inline code` ``,
// `- `/`* ` bullet lists, and triple-backtick fenced code blocks.
//
// Kept intentionally tiny so DataDrip stays dependency-free (this is an
// importmap project with no npm/bundler). If richer markdown is ever needed,
// this module is the single place to swap in a library such as
// marked (https://github.com/markedjs/marked).
//
// Styling uses inline styles on purpose: the rendered HTML is injected
// dynamically into the page, and the engine's Tailwind build cannot generate
// utilities for class names it never sees in a scanned template.

function esc(str) {
  return str.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
}

function inlineFormat(text) {
  return text
    .replace(/\*\*(.+?)\*\*/g, '<strong style="font-weight:600;color:#1e293b">$1</strong>')
    .replace(/`(.+?)`/g, '<code style="padding:1px 5px;border-radius:4px;background:#dbeafe;color:#1e40af;font-size:12px;font-family:monospace">$1</code>')
}

export function renderInstructions(text) {
  const lines = text.split("\n")
  let html = ""
  let inList = false
  let inCodeBlock = false
  let codeLines = []

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i]

    if (line.trim().match(/^```/)) {
      if (inCodeBlock) {
        html += '<pre style="margin:6px 0;padding:10px 12px;border-radius:6px;background:#1e293b;color:#e2e8f0;font-size:12px;font-family:monospace;line-height:1.5;overflow-x:auto">' + esc(codeLines.join("\n")) + "</pre>"
        codeLines = []
        inCodeBlock = false
      } else {
        if (inList) { html += "</ul>"; inList = false }
        inCodeBlock = true
      }
      continue
    }

    if (inCodeBlock) {
      codeLines.push(line)
      continue
    }

    if (line.trim() === "") {
      if (inList) { html += "</ul>"; inList = false }
      html += '<div style="height:6px"></div>'
      continue
    }

    const headerMatch = line.match(/^(#{1,3})\s+(.+)$/)
    if (headerMatch) {
      if (inList) { html += "</ul>"; inList = false }
      const level = headerMatch[1].length
      const style = level === 1
        ? "font-size:15px;font-weight:600;color:#1e3a5f;margin-bottom:2px"
        : level === 2
        ? "font-size:13px;font-weight:600;color:#2563eb;margin-bottom:2px;text-transform:uppercase;letter-spacing:0.03em"
        : "font-size:13px;font-weight:500;color:#475569;margin-bottom:2px"
      html += '<div style="' + style + '">' + inlineFormat(esc(headerMatch[2])) + "</div>"
      continue
    }

    const bulletMatch = line.match(/^[-*]\s+(.+)$/)
    if (bulletMatch) {
      if (!inList) { html += '<ul style="list-style:disc;padding-left:20px;margin:4px 0">'; inList = true }
      html += '<li style="margin-bottom:2px">' + inlineFormat(esc(bulletMatch[1])) + "</li>"
      continue
    }

    if (inList) { html += "</ul>"; inList = false }
    html += '<p style="margin-bottom:3px">' + inlineFormat(esc(line)) + "</p>"
  }

  if (inList) html += "</ul>"
  return html
}
