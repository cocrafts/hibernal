// Display strips one under the other: the button sheet's chevron end, its body stretched behind a
// line of coloured words, its pointed end after them (art/hud/cutHud.py BANNER_*).

import { Color } from "@metascript/void/src/void2d/types";
import { Ui } from "../ui/ui";
import { Kit, PieceLayer, TextSize, piece, pieceSized, pieceWidth, pieceHeight, say, measure, subId } from "./kit";

export struct BannerWord {
	text: string;
	colour: Color;
}

export struct Banner {
	words: BannerWord[];
}

const BANNER_STEP: float32 = 25.0;
const LABEL_SIZE: float32 = 8.0;
const TEXT_INSET: float32 = 15.0;
const WORD_GAP: float32 = 5.0;
const TEXT_PAD: float32 = 4.0;
const WORDS_MAX: int32 = 4;
const PARTS: int32 = 3 + WORDS_MAX;

export function bannersHeight(kit: Kit, rows: int32): float32 {
	return rows > 0 ? BANNER_STEP * ((rows - 1) as float32) + pieceHeight(kit, "bannerBody") : (0.0 as float32);
}

// `left` is the chevron ends' left edge.
export function banners(ui: Ui, kit: Kit, id: int32, left: float32, top: float32, rows: Banner[]): void {
	const height: float32 = pieceHeight(kit, "bannerBody");
	const startWidth: float32 = pieceWidth(kit, "bannerStart");
	for (let row: int32 = 0; row < (rows.length as int32); row += 1) {
		const banner: Banner = rows[row];
		if ((banner.words.length as int32) > WORDS_MAX) {
			console.log("banners: row " + row.toString() + " has " + banner.words.length.toString() + " words, at most "
				+ WORDS_MAX.toString());
			unreachable;
		}
		const y: float32 = top + BANNER_STEP * (row as float32);
		const middle: float32 = y + height * 0.5;
		let words: float32 = 0.0;
		for (const word of banner.words) {
			words += measure(kit, word.text, LABEL_SIZE).width + WORD_GAP;
		}
		const inner: float32 = Math.max(startWidth, TEXT_INSET + words - WORD_GAP + TEXT_PAD);
		const bodyLeft: float32 = left + startWidth;
		const bodyRight: float32 = left + inner;
		let x: float32 = left + TEXT_INSET;
		for (let index: int32 = 0; index < (banner.words.length as int32); index += 1) {
			const word: BannerWord = banner.words[index];
			const size: TextSize = measure(kit, word.text, LABEL_SIZE);
			say(ui, kit, subId(id, row * PARTS + 3 + index), word.text, x, middle - LABEL_SIZE * 0.625, size.width + 2.0, LABEL_SIZE,
				word.colour, 0.0);
			x += size.width + WORD_GAP;
		}
		piece(kit, subId(id, row * PARTS), PieceLayer.Frames, "bannerStart", left, y);
		pieceSized(kit, subId(id, row * PARTS + 1), PieceLayer.Frames, "bannerBody", bodyLeft, y, bodyRight - bodyLeft, height);
		piece(kit, subId(id, row * PARTS + 2), PieceLayer.Frames, "bannerEnd", bodyRight, y);
	}
}
