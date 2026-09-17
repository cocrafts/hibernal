import { HBRN_UNIT } from "../rules/index";
import { WORLD_BLOCKS, EPISODE_EPOCHS, percentile, medianEpoch } from "./world";
import { playEpisode } from "./teacher";

function main(): int32 {
	const world = playEpisode(WORLD_BLOCKS, EPISODE_EPOCHS, 7);
	const wealth = world.sortedWealth();
	const median = Math.max(percentile(wealth, 50), 1);
	console.log(`pets ${world.pets.length} living ${world.living()} heirs ${world.stats.heirs} deaths ${world.stats.deaths}`);
	console.log(`fights ${world.stats.fights} wins ${world.stats.wins} illegal ${world.stats.illegal}`);
	console.log(`level median ${world.medianLevel()} · day of level 10 ${medianEpoch(world.levelTenEpochs)} · level 20 ${medianEpoch(world.levelTwentyEpochs)}`);
	console.log(`wealth p50 ${percentile(wealth, 50) / HBRN_UNIT} p90 x${percentile(wealth, 90) * 100 / median} p99 x${percentile(wealth, 99) * 100 / median} top x${percentile(wealth, 100) * 100 / median} (x100)`);
	console.log(`burned ${world.global.burned / HBRN_UNIT} protocol ${world.global.protocolPending / HBRN_UNIT} workPower ${world.global.totalWorkPower}`);
	return 0;
}
process.exit(main());
