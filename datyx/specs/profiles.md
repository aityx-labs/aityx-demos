# Profiles

The person behind a sign-in, and the owner of what they add. Code in
`datyx-api/src/main/java/datyx/profile/` and `datyx/crypto/`.

## The entities

- `Profile` (table `profile`): `id`, `name` (the first identity's name,
  else its email; `Local` for the local profile), `createdAt`, and
  `keyWrapped`: the profile's own encryption key, 32 random bytes made
  with the profile and stored encrypted by the server's master key
  (below). Never answered.
- `ProfileIdentity` (table `profile_identity`): one sign-in the profile
  answers to: `issuer` and `subject` (unique together: a Google account's
  stable id under `https://accounts.google.com`), the claims last seen
  (`email`, `name`, `picture`), `addedAt`, `lastSeenAt`, and the
  `profile` it belongs to (`profile_id`, cascade on delete). A profile
  has one or more identities, so it is not bound to one email; adding a
  second identity to a profile, and sharing a profile between people,
  come later.

## Resolution

`Profiles` (request-scoped) finds the caller's profile once per call, by
the token's `iss` and `sub` (`CurrentUser`, [auth.md](auth.md)). An
identity the API has not seen gets a new profile with a new key, in a
transaction of its own (`ProfileMaker`), so an identity's first two calls
at once make one profile: the loser's unique violation is swallowed and
the winner's row found. Every call also records the identity's claims
and `lastSeenAt`. With authentication off every call is the local
identity, issuer `local`, subject `anonymous`, and one local profile owns
everything, so the API runs without any setup. The sign-in is simply the
first call: `GET /api/me`, which the apps make once signed in.

## Encryption at rest

`Crypto` (AES-256-GCM, `javax.crypto`): the master key,
`datyx.master-key` from `DATYX_MASTER_KEY` (32 bytes in base64,
`openssl rand -base64 32`), wraps every profile key; a profile key
encrypts the profile's records. A document is a random 12-byte nonce,
the ciphertext and a 16-byte tag, with the record's place as associated
data (`datyx:profile:<id>`), so a document can't be moved to another
profile's row. What is encrypted so far: a data source's access details,
the whole document (host, port, database, user, password, bucket,
region, endpoint, prefix, keys, path; [data-sources.md](data-sources.md)).
Without `DATYX_MASTER_KEY` the API starts in dev and test modes on a
known development key, with a warning, and refuses to start otherwise
(a jar, the native executable, Docker), naming the variable. Losing the
master key loses every profile key and everything encrypted. The key
never leaves the server: the apps see decrypted details, secrets
excepted, through the API only.

## Endpoints

- `GET /api/profile`, secured like the data sources:
  `{"id":1,"name":"Alice","createdAt":"...","dataSources":2,"identities":[{"issuer":"https://accounts.google.com","subject":"...","email":"alice@example.com","name":"Alice","picture":"...","addedAt":"...","lastSeenAt":"..."}]}`.
- `GET /api/me` carries `profileId` ([auth.md](auth.md)).

## Tests

`ProfileTest` (the `AuthOnTest` profile, the OIDC test server as the
issuer): a first call makes a profile, the next finds it and updates the
name claim, another person gets another profile, no token no profile;
each profile lists, reads and removes its own data sources only, the
same name is fine across profiles and a 409 within one; the row of a
database source holds none of its host, database, user, password or
engine in clear, and the API reads it back. `CryptoTest`, no Quarkus:
documents round-trip, and another key, place or master key is refused;
a master key that isn't base64 or isn't 32 bytes is refused.
`AuthOffTest`: the local profile.

## Known limitations

- One identity per profile so far: no endpoint links a second sign-in to
  an existing profile, and nothing is shared between profiles.
- One master key, no rotation: changing it means re-wrapping every
  profile key, which nothing does yet.
- A profile is never removed.
