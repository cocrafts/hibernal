import { backdrop, Nav, ScreenContext } from "./screenChrome";
import { digestScreen } from "./digestScreen";
import { blockScreen } from "./blockScreen";
import { petScreen } from "./petScreen";
import { shopScreen } from "./shopScreen";
import { settingsScreen } from "./settingsScreen";

// The dock tab or Settings, drawn over a dark backdrop.
export function screenFrame(context: ScreenContext, screen: Nav): void {
	context.overlayOpen = false;
	backdrop(context.kit);
	match (screen) {
		Nav.Digest => digestScreen(context),
		Nav.Block => blockScreen(context),
		Nav.Pet => petScreen(context),
		Nav.Shop => shopScreen(context),
		Nav.Settings => settingsScreen(context),
		_ => {},
	};
}
