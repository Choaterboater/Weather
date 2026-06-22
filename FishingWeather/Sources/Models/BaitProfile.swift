import Foundation

/// Static "encyclopedia" tackle and technique guidance per species. This is
/// the deterministic counterpart to the live, conditions-aware BaitEngine —
/// the BaitEngine adapts to today's weather; BaitProfile is what would always
/// be a reasonable starting point.
struct BaitProfile {
    let species: Species
    let baits: [String]
    let techniques: [String]
    let habitatHint: String
    let bestTimeOfDay: String

    static func profile(for species: Species) -> BaitProfile {
        switch species {
        case .all:
            return BaitProfile(
                species: .all,
                baits: [],
                techniques: [],
                habitatHint: "Pick a species for tailored guidance.",
                bestTimeOfDay: "Dawn and dusk are usually best."
            )
        case .bass:
            return BaitProfile(
                species: .bass,
                baits: [
                    "Plastic worm (green pumpkin, watermelon)",
                    "Jig-and-pig (black/blue)",
                    "Topwater frog or popper",
                    "Spinnerbait (chartreuse/white)"
                ],
                techniques: [
                    "Texas-rig along weed edges and laydowns",
                    "Skip jigs under docks at midday",
                    "Walk-the-dog topwater at first light",
                    "Slow-roll spinnerbaits over points in spring"
                ],
                habitatHint: "Structure-oriented: points, weedlines, laydowns, docks.",
                bestTimeOfDay: "Dawn topwater; midday on shaded structure."
            )
        case .crappie:
            return BaitProfile(
                species: .crappie,
                baits: [
                    "1/16–1/32 oz marabou or hair jig",
                    "Small minnow under a slip-cork",
                    "2\" curl-tail grub"
                ],
                techniques: [
                    "Spider-rig along brush piles",
                    "Vertical-jig under standing timber",
                    "Tight-line minnows around docks"
                ],
                habitatHint: "Submerged brush, standing timber, docks, bridge pilings.",
                bestTimeOfDay: "Pre-spawn afternoons; summer evenings."
            )
        case .catfish:
            return BaitProfile(
                species: .catfish,
                baits: [
                    "Cut bait (shad, skipjack)",
                    "Chicken liver / dough bait",
                    "Live bluegill for flatheads"
                ],
                techniques: [
                    "Anchor near channel edges with cut bait",
                    "Drift sandbars with slip-sinker rigs",
                    "Soak liver baits in slow eddies after dark"
                ],
                habitatHint: "Channels, holes, current breaks, woody cover.",
                bestTimeOfDay: "After dark — channel cats feed all night."
            )
        case .bluegill:
            return BaitProfile(
                species: .bluegill,
                baits: [
                    "Live cricket or red worm",
                    "Small popper or sponge spider on a fly rod",
                    "1\" curl-tail grub on a 1/64 oz jig"
                ],
                techniques: [
                    "Drift bait under a float on shallow flats",
                    "Bed-fish during full moons in late spring",
                    "Fly-fish poppers along brushy banks"
                ],
                habitatHint: "Shallow flats, bedding areas, brushy banks.",
                bestTimeOfDay: "Mid-morning sun on the beds."
            )
        case .redfish:
            return BaitProfile(
                species: .redfish,
                baits: [
                    "Live or cut shrimp on a Carolina rig",
                    "Gold spoon",
                    "Soft plastic paddletail (chartreuse/glow)",
                    "Cut mullet on the bottom"
                ],
                techniques: [
                    "Sight-fish tailing reds in 1–2 ft on the flats",
                    "Cast spoons to oyster bars on a moving tide",
                    "Slow-troll cut bait in deeper bay holes"
                ],
                habitatHint: "Grass flats, oyster bars, marsh drains, mangrove edges.",
                bestTimeOfDay: "Moving water around hi or low tide."
            )
        case .speckledTrout:
            return BaitProfile(
                species: .speckledTrout,
                baits: [
                    "Soft plastic under a popping cork",
                    "MirrOlure 17MR or 28 suspending twitchbait",
                    "Live shrimp on a jighead",
                    "Topwater (She Dog, Skitterwalk) at dawn"
                ],
                techniques: [
                    "Drift grass flats with popping cork rigs",
                    "Walk topwaters at first light",
                    "Twitch suspending lures around potholes"
                ],
                habitatHint: "Grass flats, potholes, drop-offs, channel edges.",
                bestTimeOfDay: "First and last light; tide turns."
            )
        case .pompano:
            return BaitProfile(
                species: .pompano,
                baits: [
                    "Sand fleas (live or molded)",
                    "Fresh-peeled shrimp",
                    "Pompano jig (yellow or pink)"
                ],
                techniques: [
                    "Fish surf troughs on a rising tide",
                    "Long-cast pompano rigs with sand fleas",
                    "Bounce small jigs along the second bar"
                ],
                habitatHint: "Surf zones, troughs and sandbars, inlet edges.",
                bestTimeOfDay: "Rising tide morning into midday."
            )
        case .flounder:
            return BaitProfile(
                species: .flounder,
                baits: [
                    "Live mud minnow or finger mullet",
                    "Gulp shrimp on a 1/4 oz jighead",
                    "Bucktail tipped with squid"
                ],
                techniques: [
                    "Slow-drag bottom presentations across sandy bottoms",
                    "Pause near structure — flounder ambush",
                    "Drift broken bottom near inlets"
                ],
                habitatHint: "Sandy bottoms near structure; inlet mouths during the run.",
                bestTimeOfDay: "Fall run on outgoing tides."
            )
        case .sheepshead:
            return BaitProfile(
                species: .sheepshead,
                baits: [
                    "Fiddler crab on a small live-bait hook",
                    "Half a fresh shrimp",
                    "Barnacle scraping (chum)"
                ],
                techniques: [
                    "Fish pilings tight to the structure",
                    "Use 1/0 hook + light fluorocarbon",
                    "Set fast — sheepshead bite quick and quiet"
                ],
                habitatHint: "Bridge pilings, dock posts, jetty rocks, reefs.",
                bestTimeOfDay: "Tide change; spring spawn aggregations."
            )
        case .snook:
            return BaitProfile(
                species: .snook,
                baits: [
                    "Live pinfish or sardine",
                    "DOA Bait Buster or jerk shad",
                    "Topwater walking lure at dawn"
                ],
                techniques: [
                    "Pitch under mangrove canopies on outgoing tide",
                    "Work dock lights after dark with twitchbaits",
                    "Live-line bait in inlet currents"
                ],
                habitatHint: "Mangroves, dock lights, passes and inlets.",
                bestTimeOfDay: "Moving tide in low light; night dock-light fishing."
            )
        case .mangroveSnapper:
            return BaitProfile(
                species: .mangroveSnapper,
                baits: [
                    "Live shrimp",
                    "Small pinfish or pilchard",
                    "Frozen Spanish sardine (cut)"
                ],
                techniques: [
                    "Light fluorocarbon leader — they're line-shy",
                    "Bottom-fish reefs and wrecks with chum",
                    "Free-line live shrimp under mangrove edges"
                ],
                habitatHint: "Mangrove shorelines, bridges, nearshore reefs and wrecks.",
                bestTimeOfDay: "After dark on bridges; mid-tide on reefs."
            )
        }
    }
}
