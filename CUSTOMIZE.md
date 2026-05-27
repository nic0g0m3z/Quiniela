# Customizing your Quiniela app

All visual changes happen in **`index.html`**. The file is organized so the easiest stuff to change sits near the top.

> 💡 **Tip**: Before any change, open `index.html` and **double-click it** to preview locally. Edit → save → refresh the browser → see your change. Only push to GitHub once you're happy.

---

## Quick reference: where everything lives

Open `index.html` and you'll find these sections in order:

| Section | What's in it | Search for |
|---|---|---|
| **Theme variables** (in `<style>`) | All colors and fonts | `:root {` |
| **Supabase config** (in `<script>`) | URL & key | `SUPABASE_URL` |
| **Scoring rules** | Points per result | `POINTS_EXACT` |
| **Components** | The actual UI and text | `function AuthScreen` etc. |

Use **Ctrl/Cmd + F** to find anything.

---

## 1. Changing colors

Near the top inside `<style>` you'll find:

```css
:root {
  --bg-base: #0a0a0a;            /* page background */
  --bg-card: #161616;            /* card background */
  --border: #262626;             /* default border */
  --text: #f5f5f5;               /* main text */
  --text-muted: #a3a3a3;         /* secondary text */
  --accent: #d4ff3a;             /* PRIMARY ACCENT (lime) */
  --accent-hover: #bfeb20;       /* button hover state */
  --danger: #ff6b6b;             /* errors and danger zones */
  --success: #5ee08a;            /* exact predictions */
  --warning: #ffc94a;            /* correct outcomes */
  --admin: #d18aff;              /* admin badges */
  ...
}
```

These are **CSS variables**. Change one, and *every place that uses it* updates. To make the app blue instead of lime, just change two values:

```css
--accent: #3b82f6;
--accent-hover: #2563eb;
```

Some accent palette ideas (pick a main + hover pair):

| Style | `--accent` | `--accent-hover` |
|---|---|---|
| Bright blue | `#3b82f6` | `#2563eb` |
| Crimson red | `#ef4444` | `#dc2626` |
| Forest green | `#22c55e` | `#16a34a` |
| Orange | `#f97316` | `#ea580c` |
| Purple | `#a855f7` | `#9333ea` |
| Cyan | `#06b6d4` | `#0891b2` |
| Pink | `#ec4899` | `#db2777` |

If you go with a **lighter accent** (like white-ish), also change `color: var(--bg-base)` in `.btn-primary` to something dark for readability:

```css
.btn-primary { background: var(--accent); color: #fff; }  /* change #fff if needed */
```

---

## 2. Changing fonts

At the top of the file, find the Google Fonts link:

```html
<link href="https://fonts.googleapis.com/css2?family=Bebas+Neue&family=Manrope:wght@400;500;600;700;800&display=swap" rel="stylesheet">
```

To use different fonts:

1. Go to **fonts.google.com**
2. Pick a font, click "Get embed code"
3. Copy the `<link>` they give you, replace the one above
4. In the `:root` block, update:
   ```css
   --font-body: 'YourFont', sans-serif;       /* normal text */
   --font-display: 'YourBigFont', sans-serif; /* big headings (QUINIELA) */
   ```

Cool combinations for a sports vibe:
- Display: **Anton**, **Oswald**, **Archivo Black**, **Bungee** · Body: **Inter**, **DM Sans**, **Manrope**
- For a magazine look: Display: **Playfair Display** · Body: **Lora**

---

## 3. Changing text on the screen

Search for the text in `index.html`. Common ones:

| What you see | Search for |
|---|---|
| Header logo "QUINIELA" | `>QUINIELA<` |
| Login tagline "Predict. Compete..." | `Predict.` |
| Dashboard heading "YOUR QUINIELAS" | `YOUR QUINIELAS` |
| "New quiniela" button | `New quiniela` |
| "Join with invite code" label | `Join with invite code` |
| Leaderboard column headers | `Player` |
| Match badges (open/locked/finished) | `badge-` (the value is set lower) |
| Scoring legend footer | `Tie-break:` |
| Danger zone heading | `Danger zone` |

Just change the text between the JSX tags (`>text<`) — don't touch the tag names or attributes.

---

## 4. Changing scoring rules

Find this block (near the top of the `<script>`):

```js
const POINTS_EXACT = 5;
const POINTS_OUTCOME = 2;
```

Change the numbers. **That's it.** The leaderboard recomputes on the fly, so all past predictions get rescored automatically with the new rule — no database changes needed.

### More complex scoring

Find the `scorePrediction` function:

```js
const scorePrediction = (pred, match) => {
  if (!pred || match.home_score == null || match.away_score == null) return 0;
  if (pred.home_score === match.home_score && pred.away_score === match.away_score) return POINTS_EXACT;
  if (outcomeOf(pred.home_score, pred.away_score) === outcomeOf(match.home_score, match.away_score)) return POINTS_OUTCOME;
  return 0;
};
```

Replace with one of these for different rules:

**Tier 3: "partial" credit (got winner right + ONE score right)**
```js
const POINTS_EXACT = 5;
const POINTS_PARTIAL = 3;
const POINTS_OUTCOME = 2;

const scorePrediction = (pred, match) => {
  if (!pred || match.home_score == null || match.away_score == null) return 0;
  const eh = pred.home_score === match.home_score;
  const ea = pred.away_score === match.away_score;
  const same = outcomeOf(pred.home_score, pred.away_score) === outcomeOf(match.home_score, match.away_score);
  if (eh && ea) return POINTS_EXACT;
  if (same && (eh || ea)) return POINTS_PARTIAL;
  if (same) return POINTS_OUTCOME;
  return 0;
};
```

**Bonus for predicting draws (because they're harder):**
```js
const scorePrediction = (pred, match) => {
  if (!pred || match.home_score == null || match.away_score == null) return 0;
  if (pred.home_score === match.home_score && pred.away_score === match.away_score) return POINTS_EXACT;
  if (outcomeOf(pred.home_score, pred.away_score) === outcomeOf(match.home_score, match.away_score)) {
    return match.home_score === match.away_score ? 4 : POINTS_OUTCOME;
  }
  return 0;
};
```

**Penalize wrong predictions (-1 point):**
```js
const scorePrediction = (pred, match) => {
  if (!pred || match.home_score == null || match.away_score == null) return 0;
  if (pred.home_score === match.home_score && pred.away_score === match.away_score) return POINTS_EXACT;
  if (outcomeOf(pred.home_score, pred.away_score) === outcomeOf(match.home_score, match.away_score)) return POINTS_OUTCOME;
  return -1;
};
```

After changing scoring, also update the legend text near the bottom of `LeaderboardTab` so it matches:

```jsx
Exact: <strong>{POINTS_EXACT}pts</strong> · Outcome: <strong>{POINTS_OUTCOME}pts</strong> · Wrong: 0pts.
```

If you used `{POINTS_EXACT}` and `{POINTS_OUTCOME}` variables, this auto-updates. If you hardcoded numbers, change them by hand.

---

## 5. Invite code length

Find `genCode`:

```js
const genCode = () => Math.random().toString(36).slice(2, 8).toUpperCase();
```

The `8` is the end index. Code length = `8 - 2 = 6` characters. Change `8` to `10` for 8-character codes. (Note: you'd also want to update the placeholder text in the join input.)

---

## 6. The 30-second match lock interval

The app re-renders every 30 seconds so kickoff-based locks update without a refresh. Find:

```js
const t = setInterval(() => setTick(x => x + 1), 30000);
```

`30000` is milliseconds. Change to `10000` for 10-second updates, `60000` for 60. More frequent = more responsive locking but more browser work. 30s is a good default.

---

## 7. Layout / spacing tweaks

Most padding/sizing is in the `<style>` block. Common changes:

- **Wider page**: search for `max-width:1100px` → change to `1300px`
- **More compact cards**: search for `.card{...padding:20px}` → change to `16px`
- **Bigger headings**: search for `style={{ fontSize: 34 }}` (the dashboard heading) → bump up

---

## 8. After making changes

### Testing locally
Save the file, **refresh** the browser tab where you opened `index.html`. Changes appear immediately. No build step.

### Pushing live (Vercel)
- **Via GitHub web**: go to your repo → edit `index.html` → commit → Vercel auto-deploys in ~30s
- **Via local editor**: edit, save, drag-drop the file into GitHub (replace the existing one) → auto-deploys

---

## What NOT to change without understanding it

A few things have subtle gotchas:

- **`useState`, `useEffect`, `useMemo`** — these are React hooks. Don't move them inside `if` blocks or loops; they need to be at the top of components.
- **The Supabase queries** (anything with `sb.from(...)`) — the field names match your database tables. Renaming a field here requires renaming it in `supabase-setup.sql` too.
- **The auth-state listener** (`sb.auth.onAuthStateChange`) — controls how the app responds to login/logout. Best left alone.
- **The RLS policies in Supabase** — these enforce security. Don't tweak unless you really know what you're doing.
- **The `sync_worldcup_2026()` function in SQL** — handles all the auto-import logic. Modifying it could break the auto-sync.

---

## Adding new features (general approach)

If you want to add something like a "comments" feature on matches:

1. **Database** — add a new table in Supabase via the SQL Editor (e.g. `comments`)
2. **Security** — write RLS policies for it (start by mirroring how `predictions` policies look)
3. **UI** — add a new section in `MatchCard` that reads and writes from the new table
4. **State** — load the data in `QuinielaView`'s `load` function, pass it down as a prop

For more ambitious changes (like the auto-fetching of real football data), you'd add a Supabase Edge Function and a Cron schedule — that's a bigger project that's worth doing once you've used the app for a tournament and know what you need.

---

## Common "I broke it" recoveries

**The page is blank**
- You probably have a JavaScript syntax error. Press **F12** → **Console** tab — the red error tells you which line is broken. Undo your last change.

**Everything looks weird/unstyled**
- You probably broke a CSS rule (missing `}` or `;`). Same fix: F12 → check for errors.

**Login screen keeps appearing even after sign-in**
- The Supabase URL or anon key is wrong. Double-check Part 2 of SETUP.md.

**Recovery strategy for any worst case**
- GitHub keeps every version! Go to your repo → click `index.html` → click **History** → find the last working version → "Revert" or copy its content. You can't truly break things permanently.

---

Have fun!
