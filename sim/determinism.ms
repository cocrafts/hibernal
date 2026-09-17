import {
	ENGINE_FIGHTS,
	digestFights,
	digestTree,
	digestEconomy,
	digestOdds,
	digestWorld,
	digestObserve,
	engineVersion,
} from "./digests";

function main(): int32 {
	console.log("fights   " + String(digestFights(ENGINE_FIGHTS)));
	console.log("tree     " + String(digestTree()));
	console.log("economy  " + String(digestEconomy()));
	console.log("odds     " + String(digestOdds()));
	console.log("world    " + String(digestWorld()));
	console.log("observe  " + String(digestObserve()));
	console.log("engine   " + String(engineVersion()));
	return 0;
}
process.exit(main());
