# Data pack format 1

Use `client/packs/*.json` as complete examples. JSON is the downloadable game definition and its asset data. UTF-8 payloads are capped at 1 MiB; a pack contains at most 100 stations, 32 item types, and 64 model parts per station.

| Field | Meaning |
| --- | --- |
| `format` | `1` |
| `id` | Stable lowercase ID, 1–48 letters/digits/underscores/hyphens |
| `version` | Increasing positive version (use integers) |
| `title`, `description` | Library card text, at most 500 characters |
| `starting_cash` | Initial balance for a new save |
| `theme` | `ground`, `accent`, `player`: 6-digit hexadecimal colors |
| `items` | Objects with unique `id` and hexadecimal `color` |
| `stations` | Station definitions |

Every station needs `id`, `kind`, `name`, `position` `[x,z]`, `cost`, `cycle`, `capacity`, and `price`. Positions are inside [-18,18]. Keep stations at least 3 units apart and keep the spawn at `[0,6]` clear. Interactions trigger within 2.1 units; station collision footprint is fixed at 1.5 × 0.8 units.

| Kind | Behavior | Extra fields |
| --- | --- | --- |
| `source` | Generates one output each cycle up to capacity | `output` |
| `processor` | Consumes one delivered input to make one output | `input`, `output` |
| `shop` | Consumes delivered stock per cycle; cash waits for collection | `input`, `price` |
| `worker` | Transfers one matching item to assigned station each cycle | `target` |
| `decoration` | Purchasable cosmetic prop | none |

A zero-cost station begins unlocked. Other stations become purchasable once every station in `requires` is unlocked. Circular prerequisites are rejected. Purchase pads spend cash gradually and retain partial payments in saves. A helper's `target` should be a shop or processor; it gathers matching output from any unlocked source/processor.

### Custom props

Set `visual` to a list of parts. This replaces the station's default prop, while its pad, label, behavior and collision stay the same. Positions are local to the station. Size is full width/height/depth; sphere/cylinder/cone parts may be stretched. Model part coordinates range from -5 to 5 and sizes from .01 to 5.

```json
"visual": [
  {"shape":"box", "position":[0,0.55,0], "size":[2.3,1.1,1.1], "color":"f6ecd9"},
  {"shape":"box", "position":[0,1.15,0], "size":[2.5,0.15,1.3], "color":"49b98b"},
  {"shape":"cone", "position":[0,2,0], "size":[2.6,1.2,1.6], "color":"e36559"}
]
```

Supported shapes: `box`, `sphere`, `cylinder`, `cone`. Models are data, rendered natively by the shared engine. There are no remote scripts or external model/texture files in format 1.

### Catalog contract

`GET /catalog.json` returns `{"format":1,"packs":[...]}`. Entries include `id`, `version`, `title`, `description`, `sha256` and `size`. `GET /packs/<id>.json` returns the exact bytes matching the hash. A failed hash or validation leaves the previous installed version intact. SHA-256 detects corruption/version races; HTTPS authenticates the server. No publisher-signature infrastructure is implemented.

You can statically host the pack directory plus a generated catalog. Run the included server's `CatalogServer.catalog()` to generate the catalog; hashes must be computed from the actual hosted bytes. Avoid transformations that reformat JSON after computing the hash.
