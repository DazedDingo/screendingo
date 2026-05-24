# ScreenDingo — Privacy Policy

_Last updated: 2026-05-24_

This document describes how the ScreenDingo Android app handles personal
information. It applies to the version distributed via Google Play and
the sideload APKs available from this repository's GitHub Releases.

**Data controller**: Zachary Birney, trading as DazedDingo. Contact:
zachbirney@gmail.com. (A postal address will be added before the Play
listing goes live, as required by Google Play's developer-disclosure
policy and EU/UK GDPR Article 13.)

## TL;DR

- We store your account info, the titles you've watched / rated / saved,
  and your two-person household pairing in Google Firebase.
- We do not sell your data, and we do not run third-party advertising or
  analytics SDKs.
- Linking your Trakt account is optional; if you do, watch + rating data
  flows between ScreenDingo and Trakt as you'd expect.
- You can delete your account and all associated data at any time from
  the in-app Profile screen.

## What we collect and why

| Data | Why | Where it's stored |
|---|---|---|
| Google account identity (uid, display name, email) | To sign you in and pair your household | Firebase Auth (Google Cloud, EU) |
| Household ID and partner uid | To share recommendations between the two members of a household | Firestore (Google Cloud, EU) |
| Watch history (movie/TV titles you've marked watched or watching) | To improve recommendations and surface "Up next" | Firestore |
| Ratings and review notes | To improve recommendations and (optionally) sync to your Trakt account | Firestore |
| Watchlist (saved titles) | To surface "Saved" in your library | Firestore |
| Taste profiles (genre/runtime/era weightings derived from your ratings) | To score recommendations | Firestore |
| Concierge / "More like these" chat history | To let the AI helper remember context across turns | Firestore |
| Trakt OAuth refresh token (if you link Trakt) | To sync watch + rating data | Firestore, encrypted at rest |
| Device-level preferences (dark mode, accent colour, view mode toggle) | To apply your UI choices on launch | Local SharedPreferences (on your device only) |
| Firebase Cloud Messaging device token | To send notifications about new episodes, badges, and partner activity | Firebase, scoped to your account |

We do not collect: precise location, contact lists, SMS, photos beyond
the share-intent flow, microphone audio, camera footage, advertising
identifiers, browsing activity outside the app, or any biometric data.

## What we share with third parties

| Service | What we send | Why |
|---|---|---|
| [TMDB](https://www.themoviedb.org/) | Movie / TV title IDs and keyword queries — never your account info | Fetching cover art, cast, episode metadata |
| [Trakt](https://trakt.tv/) | If you've linked Trakt: ratings you submit, watch entries you log | Two-way sync; optional |
| [Google Cloud (Firebase)](https://firebase.google.com/) | All app data described above | Hosting + auth + functions |
| [Google Gemini](https://ai.google.dev/) | A short prompt containing genre tags / titles when you ask for recommendations or chat with the concierge | AI scoring + chat |
| [OMDb](https://www.omdbapi.com/) | IMDb IDs of titles you view | Fetching IMDb / Rotten Tomatoes / Metacritic scores |
| [Reddit](https://www.reddit.com/) | Public title search queries (no account data) | "What people are saying" surface |
| [GitHub](https://github.com/) | Anonymised bug-report text if you submit an in-app issue | Issue tracking |

We never sell, rent, or trade your data. The third parties listed above
operate under their own privacy policies, linked above.

## Data retention and deletion

- Your data persists until you delete it.
- From the in-app **Profile** screen, you can:
  - Sign out (clears local prefs)
  - Leave your household (removes you and your data from the shared
    household; if you're the last member, deletes the household)
  - Revoke Trakt linking (deletes the stored Trakt refresh token)
- To delete your entire account and all associated data, email
  **zachbirney@gmail.com** with the subject "ScreenDingo deletion request"
  from the email address linked to your account; data is purged within
  30 days.

## Security

- All network traffic uses HTTPS.
- Firebase Authentication tokens are short-lived and managed by Google.
- Firestore access is gated by per-household security rules — no client
  can read or write data outside their own household.
- Trakt refresh tokens are stored encrypted at rest in your member
  document.
- We do not knowingly collect data from children under 13. If you
  believe a child has provided us with personal information, please
  contact us and we will delete it.

## Changes to this policy

We may update this policy as the app evolves. The "Last updated" date at
the top of this document indicates the most recent revision. Material
changes will be flagged in-app via the Profile screen.

## Contact

Zachary Birney (DazedDingo) — zachbirney@gmail.com

Source code, release notes, and issue tracker:
<https://github.com/DazedDingo/watchnext>
