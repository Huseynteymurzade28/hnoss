/*
Package text: display width and grapheme clusters, the measuring layer
everything that draws text builds on. No dependencies on the rest of hnoss.

	text.width("世界!")          // 5
	c, w, rest := text.next_grapheme("👍🏽ok")   // "👍🏽", 2, "ok"
	text.truncate("hello", 3)    // "hel", 3
*/
package text
