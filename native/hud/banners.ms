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

export const BANNER_STEP: float32 = 25.0;
const LABEL_SIZE: float32 = 8.0;
const TEXT_INSET: float32 = 22.0;
const WORD_GAP: float32 = 5.0;
const TEXT_PAD: float32 = 4.0;
const WORDS_MAX: int32 = 4;

export function bannersHeight(kit: Kit, rows: int32): float32 {
	return rows > 0 ? BANNER_STEP * ((rows - 1) as float32) + pieceHeight(kit, "bannerBody") : (0.0 as float32);
}

export enum BannerArt {
	Display,
	Pressable,
}

function artName(art: BannerArt, part: string): string {
	return match (art) {
		BannerArt.Display => part,
		BannerArt.Pressable => part + "Orange",
	};
}

// One strip at `left`, `y`; returns its right edge.
export function banner(ui: Ui, kit: Kit, id: int32, art: BannerArt, left: float32, y: float32, words: BannerWord[]): float32 {
	if ((words.length as int32) > WORDS_MAX) {
		console.log("banners: " + words.length.toString() + " words, at most " + WORDS_MAX.toString());
		unreachable;
	}
	const height: float32 = pieceHeight(kit, "bannerBody");
	const startWidth: float32 = pieceWidth(kit, "bannerStart");
	const middle: float32 = y + height * 0.5;
	let wordsWidth: float32 = 0.0;
	for (const word of words) {
		wordsWidth += measure(kit, word.text, LABEL_SIZE).width + WORD_GAP;
	}
	const inner: float32 = Math.max(startWidth, TEXT_INSET + wordsWidth - WORD_GAP + TEXT_PAD);
	const bodyLeft: float32 = left + startWidth;
	const bodyRight: float32 = left + inner;
	let x: float32 = left + TEXT_INSET;
	for (let index: int32 = 0; index < (words.length as int32); index += 1) {
		const word: BannerWord = words[index];
		const size: TextSize = measure(kit, word.text, LABEL_SIZE);
		say(ui, kit, subId(id, 3 + index), word.text, x, middle - LABEL_SIZE * 0.625, size.width + 2.0, LABEL_SIZE,
			word.colour, 0.0);
		x += size.width + WORD_GAP;
	}
	piece(kit, subId(id, 0), PieceLayer.Frames, artName(art, "bannerStart"), left, y);
	pieceSized(kit, subId(id, 1), PieceLayer.Frames, artName(art, "bannerBody"), bodyLeft, y, bodyRight - bodyLeft, height);
	piece(kit, subId(id, 2), PieceLayer.Frames, artName(art, "bannerEnd"), bodyRight, y);
	return bodyRight + pieceWidth(kit, "bannerEnd");
}

// `left` is the chevron ends' left edge; returns each row's right edge.
export function banners(ui: Ui, kit: Kit, id: int32, left: float32, top: float32, rows: Banner[]): float32[] {
	const rights: float32[] = [];
	for (let row: int32 = 0; row < (rows.length as int32); row += 1) {
		rights.push(banner(ui, kit, subId(id, row), BannerArt.Display, left, top + BANNER_STEP * (row as float32),
			rows[row].words));
	}
	return rights;
}
