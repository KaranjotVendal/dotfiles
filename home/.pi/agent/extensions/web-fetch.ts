import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";
import { Type } from "@sinclair/typebox";

const JINA_READER_URL = "https://r.jina.ai";
const MAX_LENGTH = 80000;

export default function (pi: ExtensionAPI) {
	pi.registerTool({
		name: "fetch",
		label: "Fetch URL",
		description: "Fetch content from a URL using Jina Reader. Returns cleaned page content. Best for articles, documentation, and readable web pages.",
		parameters: Type.Object({
			url: Type.String({ description: "The URL to fetch" }),
		}),
		async execute(toolCallId, params, signal) {
			const { url } = params as { url: string };

			try {
				const response = await fetch(`${JINA_READER_URL}/${encodeURIComponent(url)}`, {
					signal,
					headers: {
						Accept: "text/plain",
					},
				});

				if (!response.ok) {
					return {
						content: [{ type: "text", text: `HTTP error: ${response.status} ${response.statusText}` }],
						details: { error: true, status: response.status },
					};
				}

				let text = await response.text();

				if (text.length > MAX_LENGTH) {
					text = text.slice(0, MAX_LENGTH) + `\n\n[Content truncated - original length: ${text.length} chars]`;
				}

				return {
					content: [{ type: "text", text }],
					details: { url, provider: "jina-reader" },
				};
			} catch (error) {
				const message = error instanceof Error ? error.message : "Unknown error";
				return {
					content: [{ type: "text", text: `Fetch error: ${message}` }],
					details: { error: true, message },
				};
			}
		},
	});

	pi.registerTool({
		name: "web_search",
		label: "Web Search",
		description: "Search the web using Jina. Returns top search results with content summaries.",
		parameters: Type.Object({
			query: Type.String({ description: "The search query" }),
		}),
		async execute(toolCallId, params, signal) {
			const { query } = params as { query: string };

			try {
				const response = await fetch(
					`${JINA_READER_URL}/https://duckduckgo.com/?q=${encodeURIComponent(query)}&format=json`,
					{ signal }
				);

				if (!response.ok) {
					return {
						content: [{ type: "text", text: `Search error: ${response.status}` }],
						details: { error: true },
					};
				}

				const data = await response.json();

				if (data.AbstractText) {
					return {
						content: [{
							type: "text",
							text: `${data.AbstractText}\n\nSource: ${data.AbstractSource}`
						}],
						details: { query, source: "duckduckgo-via-jina" },
					};
				}

				if (data.RelatedTopics && data.RelatedTopics.length > 0) {
					const results = data.RelatedTopics.slice(0, 5).map((topic: { Text: string; FirstURL: string }) => 
						`- ${topic.Text}\n  ${topic.FirstURL}`
					).join("\n\n");

					return {
						content: [{ type: "text", text: results }],
						details: { query, source: "duckduckgo-via-jina" },
					};
				}

				return {
					content: [{ type: "text", text: "No results found" }],
					details: { query },
				};
			} catch (error) {
				const message = error instanceof Error ? error.message : "Unknown error";
				return {
					content: [{ type: "text", text: `Search error: ${message}` }],
					details: { error: true, message },
				};
			}
		},
	});
}
