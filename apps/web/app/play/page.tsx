// The Godot web export, copied into public/godot by `pnpm game` from the repo root. The town's server goes in as ?server=, which
// TownClient reads (game/scripts/client/town_client.gd); without it a web player would knock on their own machine.
const SERVER = process.env.NEXT_PUBLIC_GAME_SERVER || "ws://127.0.0.1:7878"

export default function Play() {
  return <iframe className="stage" src={`/godot/index.html?server=${encodeURIComponent(SERVER)}`} title="Dhaniverse" allow="fullscreen; autoplay" />
}
