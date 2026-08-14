import assert from "node:assert";
import test from "node:test";
import { extractTextFromDocument } from "../lib/extract-text.js";
import { JSDOM } from "jsdom";

function doc(html) {
	const dom = new JSDOM(html);
	return dom.window.document;
}

test("extracts body text when no selector is given", () => {
	const document = doc(`
		<html>
			<body>
				<h1>Hello world</h1>
				<p>This is a test.</p>
			</body>
		</html>
	`);
	const result = extractTextFromDocument(document);
	assert.match(result, /Hello world/);
	assert.match(result, /This is a test/);
});

test("extracts text from a selector", () => {
	const document = doc(`
		<html>
			<body>
				<article>
					<h2>Article title</h2>
					<p>Article body</p>
				</article>
				<aside>Sidebar noise</aside>
			</body>
		</html>
	`);
	const result = extractTextFromDocument(document, { selector: "article" });
	assert.match(result, /Article title/);
	assert.match(result, /Article body/);
	assert.doesNotMatch(result, /Sidebar noise/);
});

test("returns a clear message when selector matches nothing", () => {
	const document = doc(`<html><body><p>Only this</p></body></html>`);
	const result = extractTextFromDocument(document, { selector: "#missing" });
	assert.equal(result, "No element matches selector: #missing");
});

test("limits output length when maxLength is set", () => {
	const document = doc(`<html><body><p>${"a ".repeat(500)}</p></body></html>`);
	const result = extractTextFromDocument(document, { maxLength: 100 });
	assert.ok(result.length <= 110);
	assert.match(result, /\.\.\.$/);
});

test("returns empty document message when body has no text", () => {
	const document = doc(`<html><body></body></html>`);
	const result = extractTextFromDocument(document);
	assert.equal(result, "(No text found on page)");
});
