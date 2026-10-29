package tests

import "core:testing"
import "../text"

@(test)
text_rune_width :: proc(t: ^testing.T) {
	testing.expect_value(t, text.rune_width('a'), 1)
	testing.expect_value(t, text.rune_width('\t'), 0)
	testing.expect_value(t, text.rune_width(0x7f), 0)
	testing.expect_value(t, text.rune_width('é'), 1)
	testing.expect_value(t, text.rune_width('世'), 2)
	testing.expect_value(t, text.rune_width('한'), 2)
	testing.expect_value(t, text.rune_width('Ａ'), 2) // fullwidth A
	testing.expect_value(t, text.rune_width('🎉'), 2)
	testing.expect_value(t, text.rune_width(0x0301), 0) // combining acute
	testing.expect_value(t, text.rune_width(0x200b), 0) // zero width space
	testing.expect_value(t, text.rune_width(0x00ad), 1) // soft hyphen is drawn
	testing.expect_value(t, text.rune_width('─'), 1)
	testing.expect_value(t, text.rune_width('❤'), 1)   // text presentation by default
}

@(private = "file")
expect_cluster :: proc(t: ^testing.T, s, want: string, want_w: int, loc := #caller_location) {
	c, w, _ := text.next_grapheme(s)
	testing.expectf(t, c == want && w == want_w, "next_grapheme(%q) = %q w%d, want %q w%d", s, c, w, want, want_w, loc = loc)
}

@(test)
text_graphemes :: proc(t: ^testing.T) {
	expect_cluster(t, "ab", "a", 1)
	expect_cluster(t, "éx", "é", 1)
	expect_cluster(t, "\r\nx", "\r\n", 0)
	expect_cluster(t, "👍🏽!", "👍🏽", 2)                          // skin tone
	expect_cluster(t, "👩‍💻 hi", "👩‍💻", 2)          // ZWJ sequence
	expect_cluster(t, "👨‍👩‍👧‍👦.", "👨‍👩‍👧‍👦", 2)
	expect_cluster(t, "🇦🇿🇹🇷", "🇦🇿", 2)                          // flag = RI pair
	expect_cluster(t, "🇹🇷🇦🇿", "🇹🇷", 2)
	expect_cluster(t, "❤️", "❤️", 2)                    // VS16 widens
	expect_cluster(t, "각x", "각", 2) // Hangul jamo L V T
}

@(test)
text_width_and_truncate :: proc(t: ^testing.T) {
	testing.expect_value(t, text.width(""), 0)
	testing.expect_value(t, text.width("hello"), 5)
	testing.expect_value(t, text.width("世界!"), 5)
	testing.expect_value(t, text.width("café"), 4)
	testing.expect_value(t, text.width("🇦🇿 ok"), 5)
	testing.expect_value(t, text.width("Salam, dünya! ə"), 15)

	p, w := text.truncate("hello", 3)
	testing.expect_value(t, p, "hel")
	testing.expect_value(t, w, 3)
	p, w = text.truncate("世界", 3) // can't split the second wide char
	testing.expect_value(t, p, "世")
	testing.expect_value(t, w, 2)
	p, w = text.truncate("éé", 1)
	testing.expect_value(t, p, "é")
	p, w = text.truncate("abc", 10)
	testing.expect_value(t, p, "abc")
}
