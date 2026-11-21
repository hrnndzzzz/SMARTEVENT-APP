# The website lives in its own repository

https://github.com/sioneldaezima/smartevent-website

It used to sit in `website/` here. Two copies of the same files, with
only one of them deployed, is a trap: edit the wrong one and the live
site silently stops matching what you are looking at. So there is one
copy, and it is the one Vercel builds from.

Live at https://smartevent-website.vercel.app

Vercel deploys that repository's root on every push to `main`. Its
own README covers the design, the screenshots, and the
`POST /download-requests` endpoint the request form needs — which
does not exist yet, so the form currently tells visitors to email
CITE instead.
