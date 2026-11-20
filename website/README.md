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

A bordered console: a fixed icon rail down the left, a yellow command
strip across the top, flat bordered cards in the middle, and one
orange action bar pinned to the bottom. Hard 2px rules and flat fills
throughout — no soft shadows anywhere. Below 760px the rail becomes a
horizontally scrolling strip above the content.

The theme toggle lives in the top strip rather than at the foot of the
rail, where the reference would put it: the rail scrolls sideways on a
phone, so anything at its end sits off-screen.

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

GitHub Pages, from this folder:

1. Settings → Pages → Source: *Deploy from a branch*
2. Branch `develop`, folder `/website`
3. For the custom domain, add a `CNAME` file here containing the
   hostname, and point that name at GitHub in DNS

The URL then goes on the brochure, replacing the placeholder in
`brochure.html`.
