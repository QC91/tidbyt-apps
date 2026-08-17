"""
sports_app.star — live scores on a Tidbyt via ESPN's public scoreboard API.

Config:
    league  one of the keys in LEAGUES below (default "nfl")
    team    optional team abbreviation to pin, e.g. "SF", "GSW", "SJ"
"""

load("render.star", "render")
load("http.star", "http")
load("schema.star", "schema")

# ESPN scoreboard paths are {sport}/{league}. Add more as needed.
LEAGUES = {
    "nfl": "football/nfl",
    "ncaaf": "football/college-football",
    "nba": "basketball/nba",
    "wnba": "basketball/wnba",
    "ncaam": "basketball/mens-college-basketball",
    "mlb": "baseball/mlb",
    "nhl": "hockey/nhl",
    "mls": "soccer/usa.1",
    "epl": "soccer/eng.1",
}

ESPN_URL = "https://site.api.espn.com/apis/site/v2/sports/%s/scoreboard"

TTL_SECONDS = 30

FONT = "tom-thumb"
DIM = "#666"
BRIGHT = "#fff"
LIVE = "#3f3"

# Which game wins the screen: in-progress, then upcoming, then final.
STATE_RANK = {"in": 0, "pre": 1, "post": 2}

def main(config):
    league_key = (config.get("league") or "nfl").lower()
    team_filter = (config.get("team") or "").upper()

    path = LEAGUES.get(league_key)
    if not path:
        return message("bad league: %s" % league_key)

    resp = http.get(ESPN_URL % path, ttl_seconds = TTL_SECONDS)
    if resp.status_code != 200:
        return message("ESPN %d" % resp.status_code)

    events = resp.json().get("events", [])
    games = [g for g in [parse_game(e) for e in events] if g != None]

    if team_filter:
        games = [g for g in games if team_filter in (g["home"]["abbr"], g["away"]["abbr"])]

    if not games:
        return message("%s: no games" % league_key.upper())

    return scoreboard(league_key, pick_game(games))

def pick_game(games):
    best = games[0]
    best_rank = STATE_RANK.get(best["state"], 3)
    for g in games:
        rank = STATE_RANK.get(g["state"], 3)
        if rank < best_rank:
            best = g
            best_rank = rank
    return best

def parse_game(event):
    """Flatten one ESPN event into the fields we actually draw."""
    comps = event.get("competitions", [])
    if not comps:
        return None

    competitors = comps[0].get("competitors", [])
    if len(competitors) < 2:
        return None

    # Don't assume ordering — ESPN is not consistent about home being first.
    home = None
    away = None
    for c in competitors:
        if c.get("homeAway") == "home":
            home = c
        elif c.get("homeAway") == "away":
            away = c

    if home == None or away == None:
        return None

    status = event.get("status", {}).get("type", {})
    return {
        "state": status.get("state", "pre"),
        "detail": status.get("shortDetail", ""),
        "home": side(home),
        "away": side(away),
    }

def side(competitor):
    team = competitor.get("team", {})
    color = team.get("color", "")
    return {
        "abbr": team.get("abbreviation", "???"),
        "score": competitor.get("score", ""),
        "color": "#" + color if color else "#444",
    }

def scoreboard(league_key, game):
    live = game["state"] == "in"
    pregame = game["state"] == "pre"

    return render.Root(
        delay = 100,
        child = render.Column(
            children = [
                header(league_key, live),
                team_row(game["away"], pregame),
                team_row(game["home"], pregame),
                render.Marquee(
                    width = 64,
                    child = render.Text(
                        content = game["detail"],
                        font = FONT,
                        color = LIVE if live else DIM,
                    ),
                ),
            ],
        ),
    )

def header(league_key, live):
    children = [render.Text(content = league_key.upper(), font = FONT, color = DIM)]
    if live:
        children.append(render.Padding(
            pad = (3, 1, 0, 0),
            child = render.Circle(color = LIVE, diameter = 3),
        ))

    return render.Padding(
        pad = (1, 0, 0, 1),
        child = render.Row(children = children),
    )

def team_row(t, pregame):
    return render.Padding(
        pad = (1, 0, 2, 1),
        child = render.Row(
            expanded = True,
            main_align = "space_between",
            cross_align = "center",
            children = [
                render.Row(
                    cross_align = "center",
                    children = [
                        render.Box(width = 2, height = 7, color = t["color"]),
                        render.Padding(
                            pad = (2, 0, 0, 0),
                            child = render.Text(content = t["abbr"], font = FONT, color = BRIGHT),
                        ),
                    ],
                ),
                render.Text(
                    content = "-" if pregame else t["score"],
                    font = FONT,
                    color = BRIGHT,
                ),
            ],
        ),
    )

def message(text):
    """Always return a renderable Root — an empty render breaks pixlet push."""
    return render.Root(
        child = render.Box(
            child = render.WrappedText(content = text, font = FONT, color = DIM, align = "center"),
        ),
    )

def get_schema():
    return schema.Schema(
        version = "1",
        fields = [
            schema.Text(
                id = "league",
                name = "League",
                desc = "nfl, nba, mlb, nhl, ncaaf, ncaam, wnba, mls, epl",
                icon = "trophy",
                default = "nfl",
            ),
            schema.Text(
                id = "team",
                name = "Team abbreviation",
                desc = "Optional. Pin one team, e.g. SF. Blank shows any game.",
                icon = "shirt",
                default = "",
            ),
        ],
    )
