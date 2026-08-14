/**
 * Extract readable text from a DOM document.
 *
 * @param {Document} document
 * @param {Object} options
 * @param {string} [options.selector] - CSS selector to scope extraction to a single element.
 * @param {number} [options.maxLength] - Maximum number of characters to return.
 * @returns {string}
 */
export function extractTextFromDocument(document, options = {}) {
	const { selector, maxLength } = options;

	let root;
	if (selector) {
		root = document.querySelector(selector);
		if (!root) {
			return `No element matches selector: ${selector}`;
		}
	} else {
		root = document.body;
		if (!root) {
			return "(No text found on page)";
		}
	}

	// Clone the root so we can remove non-visible elements without mutating the document.
	const clone = root.cloneNode(true);
	for (const tag of ["script", "style", "noscript", "iframe", "canvas", "svg"]) {
		for (const el of clone.querySelectorAll(tag)) {
			el.remove();
		}
	}

	// Prefer innerText; fall back to textContent because JSDOM and some headless
	// environments do not implement innerText fully.
	let text = clone.innerText || clone.textContent || "";
	text = text.replace(/\s+/g, " ").trim();

	if (!text) {
		return "(No text found on page)";
	}

	if (maxLength && text.length > maxLength) {
		text = text.slice(0, maxLength).trim() + "...";
	}

	return text;
}
