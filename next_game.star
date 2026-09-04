"""
next_game.star — upcoming games for one team, from ESPN's team schedule endpoint.

Config:
    league  nfl, mlb, nba, nhl, ... (keys in LEAGUES)
    team    team abbreviation, e.g. "SF", "GSW", "SJ"
    count   how many upcoming games to list (1-3, default 3)

Render:
    pixlet render next_game.star league=mlb team=SF --output next_game.webp
"""

load("render.star", "render")
load("http.star", "http")
load("time.star", "time")
load("schema.star", "schema")

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

SCHEDULE_URL = "https://site.api.espn.com/apis/site/v2/sports/%s/teams/%s/schedule"

# The schedule payload is ~100KB and changes rarely — cache it hard.
TTL_SECONDS = 1800

DEFAULT_TZ = "America/Los_Angeles"

# ESPN returns e.g. "2026-09-05T23:10Z" — no seconds, so not strict RFC3339.
ESPN_TIME_FORMAT = "2006-01-02T15:04Z"

FONT = "tom-thumb"
DIM = "#666"
BRIGHT = "#fff"
ACCENT = "#fa0"

def main(config):
    league_key = (config.get("league") or "mlb").lower()
    team = (config.get("team") or "SF").upper()
    count = int(config.get("count") or "3")
    tz = config.get("$tz") or DEFAULT_TZ

    path = LEAGUES.get(league_key)
    if not path:
        return message("bad league: %s" % league_key)

    url = SCHEDULE_URL % (path, team.lower())
    resp = http.get(url, ttl_seconds = TTL_SECONDS)
    if resp.status_code != 200:
        return message("%s: ESPN %d" % (team, resp.status_code))

    events = resp.json().get("events", [])
    upcoming = []
    for e in events:
        row = parse_event(e, team, tz)
        if row != None:
            upcoming.append(row)
        if len(upcoming) >= count:
            break

    if not upcoming:
        return message("%s: no games scheduled" % team)

    return render.Root(
        delay = 100,
        child = render.Column(
            children = [header(team)] + [game_row(g) for g in upcoming],
        ),
    )

def parse_event(event, team, tz):
    """Return a drawable row for this event, or None if it isn't upcoming."""
    comps = event.get("competitions", [])
    if not comps:
        return None
    comp = comps[0]

    state = comp.get("status", {}).get("type", {}).get("state", "")
    if state != "pre":
        return None

    competitors = comp.get("competitors", [])
    if len(competitors) < 2:
        return None

    opponent = None
    at_home = True
    for c in competitors:
        abbr = c.get("team", {}).get("abbreviation", "")
        if abbr.upper() == team:
            at_home = c.get("homeAway") == "home"
        else:
            opponent = abbr

    if opponent == None:
        return None

    raw = event.get("date", "")
    if len(raw) != len(ESPN_TIME_FORMAT):
        return None

    t = time.parse_time(raw, format = ESPN_TIME_FORMAT).in_location(tz)

    return {
        "when": t.format("1/2"),
        "opp": ("v" if at_home else "@") + opponent,
        "time": t.format("3:04").lstrip("0") + t.format("PM")[0].lower(),
    }

def header(team):
    return render.Padding(
        pad = (1, 0, 0, 1),
        child = render.Row(
            expanded = True,
            main_align = "space_between",
            children = [
                render.Text(content = team, font = FONT, color = ACCENT),
                render.Text(content = "NEXT", font = FONT, color = DIM),
            ],
        ),
    )

def game_row(g):
    return render.Padding(
        pad = (1, 0, 2, 1),
        child = render.Row(
            expanded = True,
            main_align = "space_between",
            children = [
                render.Text(
                    content = "%s %s" % (g["when"], g["opp"]),
                    font = FONT,
                    color = BRIGHT,
                ),
                render.Text(content = g["time"], font = FONT, color = DIM),
            ],
        ),
    )

def message(text):
    return render.Root(
        child = render.Box(
            child = render.WrappedText(content = text, font = FONT, color = DIM, align = "center"),
        ),
    )

def get_schema():
    return schema.Schema(
        version = "1",
        fields = [
            schema.Text(id = "league", name = "League", desc = "mlb, nfl, nba, nhl", icon = "trophy", default = "mlb"),
            schema.Text(id = "team", name = "Team", desc = "Abbreviation, e.g. SF", icon = "shirt", default = "SF"),
            schema.Text(id = "count", name = "Games to show", desc = "1 to 3", icon = "listOl", default = "3"),
        ],
    )
