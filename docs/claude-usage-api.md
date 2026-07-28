# claude.ai Usage API — integration notes

Private/undocumented endpoints on claude.ai that report rate-limit utilization
for the logged-in account. No compatibility promise: field names can change
without notice. Dump the raw JSON before debugging a parse failure.

## Endpoints

```
GET https://claude.ai/api/organizations
GET https://claude.ai/api/organizations/<org_id>/usage
```

## Auth

```
Cookie: sessionKey=<key>
Accept: application/json
User-Agent: <anything>
```

`sessionKey` is the browser session cookie for a logged-in claude.ai account.

**It is a full account credential, not a scoped API key.** Anything the account
can do, a holder of this cookie can do.

- Store it in a file with mode 600, outside any repository.
- Never hardcode it, commit it, or pass it as a command-line argument (argv is
  visible to every user via `ps`).
- Never log the request object or headers — the cookie rides in there.
- Re-read the file on every pass rather than caching it in memory: session keys
  expire, and the fix should be "paste a new one into the file", not "hunt down
  and restart the process".

Getting one: browser DevTools → Application → Cookies → `claude.ai` → `sessionKey`.

## Responses

### `/organizations`

A JSON array. The org id is `[0].uuid`, falling back to `[0].id`. Accounts
normally have exactly one org; with several there is no way to guess which is
meant, so expose an override.

### `/organizations/<org_id>/usage`

A JSON object carrying the same figures **twice** — as top-level objects and as
entries in a `limits` array. Read the top-level pair first (unambiguous), fall
back to the array.

Shape A — top-level:

```json
{
  "five_hour": { "utilization": 16.0, "resets_at": "<ISO8601>" },
  "seven_day": { "utilization": 42.0, "resets_at": "<ISO8601>" }
}
```

Shape B — `limits` array:

```json
{
  "limits": [
    { "kind": "session",       "percent": 16, "resets_at": "<ISO8601>" },
    { "kind": "weekly_all",    "percent": 42, "resets_at": "<ISO8601>" },
    { "kind": "weekly_scoped", "percent": 30, "resets_at": "<ISO8601>" }
  ]
}
```

Notes:

- `utilization` is a float, `percent` is an int. Round both rather than
  truncating, so the two paths cannot disagree by a point on a value like 16.6.
- `weekly_scoped` is a **per-model** limit. `weekly_all` is the account-wide
  weekly window. Do not conflate them.
- Key names seen in the wild — session: `five_hour`. Weekly: `seven_day`,
  `weekly`, `week`, `seven_days`.

## Poll rate

60 seconds. Claude Usage Tracker, a shipped app, polls this endpoint at that
rate — evidence the rate is tolerated, which beats picking a cautious number out
of the air.

It also matches how fast the figure moves: a five-hour window going empty to
full advances about a percent every three minutes. Polling faster buys nothing;
polling slower is safe, just laggier.

## Error mapping

| Condition | Meaning |
|---|---|
| HTTP 401 / 403 | Session key expired or invalid — fetch a fresh one from the browser |
| Other HTTP status | Server-side; retry on the normal schedule |
| `CERTIFICATE_VERIFY_FAILED` | The interpreter has no CA trust store (typical of the python.org macOS build). Use Homebrew's Python, or run its `Install Certificates.command` |
| No matching window in the payload | A field was renamed — dump the raw JSON and update the key lists |

## Reference implementation (Python, stdlib only)

```python
import json, stat, urllib.request, urllib.error
from pathlib import Path

ORGS = "https://claude.ai/api/organizations"
USAGE = "https://claude.ai/api/organizations/{org_id}/usage"


def read_key(path: Path) -> str:
    """Read the session key, refusing a file other users can open."""
    mode = path.stat().st_mode
    if mode & (stat.S_IRWXG | stat.S_IRWXO):
        raise RuntimeError(f"{path} is readable by other users; chmod 600 it")
    key = path.read_text(encoding="utf-8").strip()
    if not key:
        raise RuntimeError(f"{path} is empty")
    return key


def get(url: str, key: str, timeout: int = 20):
    request = urllib.request.Request(url, headers={
        "Cookie": f"sessionKey={key}",
        "Accept": "application/json",
        "User-Agent": "my-app/1.0",
    })
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            return json.loads(response.read())
    except urllib.error.HTTPError as error:
        # Never include the request in the message: it carries the cookie.
        if error.code in (401, 403):
            raise RuntimeError(
                f"claude.ai rejected the session key (HTTP {error.code}); "
                "it has most likely expired"
            ) from None
        raise RuntimeError(f"claude.ai returned HTTP {error.code}") from None
    except urllib.error.URLError as error:
        if "CERTIFICATE_VERIFY_FAILED" in str(error.reason):
            raise RuntimeError(
                "TLS verification failed: this Python has no CA certificates"
            ) from None
        raise RuntimeError(f"cannot reach claude.ai: {error.reason}") from None


def discover_org_id(key: str) -> str:
    payload = get(ORGS, key)
    if not isinstance(payload, list) or not payload:
        raise RuntimeError("no organizations on this account")
    org_id = payload[0].get("uuid") or payload[0].get("id")
    if not org_id:
        raise RuntimeError("could not find an organization id in the response")
    return str(org_id)


def window(payload: dict, keys: tuple, kinds: tuple):
    """Find one limit window as (percent, resets_at), or None."""
    for key in keys:
        entry = payload.get(key)
        if isinstance(entry, dict) and entry.get("utilization") is not None:
            return round(entry["utilization"]), entry.get("resets_at")

    for entry in payload.get("limits") or []:
        if not isinstance(entry, dict) or entry.get("kind") not in kinds:
            continue
        if entry.get("percent") is None:
            continue
        return round(entry["percent"]), entry.get("resets_at")
    return None


def fetch(key: str, org_id: str) -> dict:
    if "/" in org_id or ".." in org_id:
        raise RuntimeError("organization id must not contain '/' or '..'")
    return get(USAGE.format(org_id=org_id), key)


key_file = Path.home() / ".config" / "claude-quota" / "session-key"
org_id = discover_org_id(read_key(key_file))          # once, at startup

usage = fetch(read_key(key_file), org_id)             # every pass
session = window(usage, ("five_hour",), ("session",))
weekly = window(
    usage, ("seven_day", "weekly", "week", "seven_days"), ("weekly_all",)
)
```

Validate `org_id` before interpolating it into the URL whenever it can come from
outside the program.

## Design principles worth carrying over

**Split the fetcher from the server.** The process holding the credential should
not be the one listening on a socket. Have the fetcher write a file and the
server only read it. Side benefit: the consumer's poll rate is decoupled from the
upstream call rate, so a second consumer or a faster poll changes nothing about
what leaves the machine.

**Write the cache atomically.** Write to `<name>.tmp`, then `Path.replace()`.
A reader must never see a half-written file.

**A failed fetch should not exit, and should not delete the previous cache.**
Leave the stale values in place and let the consumer decide they are too old,
based on the timestamp.

**Missing is not zero.** When a field is absent, omit it and warn — never
synthesize a value. A consumer showing "unknown" is telling the truth; a
consumer showing a fabricated 0% is not.

**Stamp every write with a timestamp.** Consumers need the age of the reading to
judge whether it is still fit to display.

**Keep transport outcome separate from fitness-to-use.** A healthy HTTP 200 can
still carry values too old to act on. Model "the fetch succeeded" and "the value
is trustworthy" as two different things, and never render a transport status
where a value belongs.
