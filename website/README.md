# The SMARTEVENT website

One static page: what the system is, who it is for, what it looks like,
and a form for requesting the APK. No build step and no framework — it
is `index.html`, its stylesheet inline, and the images beside it.

## Looking at it

```
python3 -m http.server 4173 --directory website
```

Then open `http://localhost:4173`. Opening `index.html` straight off
disk works too, but a server is closer to how it will be served.

## The shape of it

One yellow command bar across the top carrying the mark, the
navigation and the actions — nothing else competes with it — then flat
bordered cards down the page and a single orange action bar at the
foot. Hard 2px rules and flat fills; no soft shadows anywhere.

There was a left icon rail and a separate top strip before. Two
navigation surfaces on one page read as clutter, so they are one.
Below 860px the wordmark goes, and below 620px the links go too: the
page is one scroll, and the mark, the theme and the one action are
enough.

## Where the design comes from

The colours in `:root` are lifted from `lib/theme/app_colors.dart` and
the two faces are the app's own, so the site and the product are
plainly the same thing. Change a colour in the app and change it here
too; there is no shared source for them yet.

The screenshots in `assets/shots/` are from the running app in demo
mode, cropped past the status bar. Replace them when the screens
change — a site showing last term's UI is worse than one showing none.

## The download request

The form POSTs JSON to the endpoint named at the top of the inline
script:

```js
var ENDPOINT = 'https://api.smartevent.date/download-requests';
```

Body:

```json
{
  "name": "...",
  "email": "...",
  "organization": "...",
  "role": "officer | treasurer | adviser | sds_staff | admin",
  "reason": "..."
}
```

What the page expects back:

| Response | What the visitor is told |
| --- | --- |
| `2xx` | Request sent, the link goes to that address if approved |
| `409` | There is already a request from that address waiting |
| anything else | The server refused it; email CITE instead |
| no response | Could not reach the server; email CITE instead |

**The endpoint does not exist yet.** Until it does, every submission
falls to the last row and tells the visitor to email instead, which is
a working fallback rather than a broken form — but it is a fallback.
The backend needs to store the request, let an administrator approve
it, and email the link on approval. Resend is already wired up for the
registration confirmation, so the mail half has a pattern to follow.

CORS: the endpoint has to allow the origin the site is served from, or
the browser will block the POST and the visitor will see the
"could not reach" message with the server working perfectly.

## Publishing it

Vercel, with this folder as the project root. `vercel.json` sits here
and sets clean URLs plus cache headers for `assets/`.

**From the dashboard** (no CLI, and it redeploys on every push):

1. vercel.com → Add New → Project → import `hrnndzzzz/SMARTEVENT-APP`
2. **Root Directory: `website`** — this is the one that matters; left
   at the repo root it will try to build the Flutter app
3. Framework Preset: *Other*. No build command, no output directory
4. Deploy

**From the CLI**, if you would rather:

```
npx vercel --cwd website
```

It asks you to sign in the first time, then `npx vercel --cwd website --prod`
publishes.

For `smartevent.date`: Project → Settings → Domains, add the hostname,
and point DNS where Vercel tells you. The API already answers on
`api.smartevent.date`, so the apex or `www` is free for this.

Once it is live the URL goes on the brochure, replacing the
placeholder in `brochure.html`, and the QR code is generated from it.
