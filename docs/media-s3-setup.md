# Media storage — S3 + CloudFront

Photos and videos use a **presigned direct upload** model (same approach as the
Gopal Mandir app):

1. App calls `POST /media/presign` with the content type → API returns a
   short-lived presigned `PUT` URL, the object `key`, and the future public URL.
2. App `PUT`s the file bytes straight to S3 (bypasses the API — good for video).
3. App calls `POST /media/confirm` → API stores the row (with the usual
   auto-approve / pending-moderation rule) and returns the public read URL.

Reads are served from a **public** CloudFront (or S3) base URL — no per-request
signing. Keys are unguessable UUIDs and the gallery only lists approved rows.

When `MEDIA_BACKEND=local` (default) the same 3-step flow runs against the API's
own signed `/media/blob` (upload) and `/media/files` (download) endpoints, so the
mobile client has a single code path.

## Backend config

Set these on the API (Railway / `.env`):

```
MEDIA_BACKEND=s3
S3_BUCKET=sabarimala-yatra-media
AWS_REGION=ap-south-1
AWS_ACCESS_KEY_ID=...
AWS_SECRET_ACCESS_KEY=...
# Public read base (no trailing slash). Prefer CloudFront:
MEDIA_PUBLIC_BASE_URL=https://dxxxxxxxxxxxx.cloudfront.net
# Or, without CloudFront, the S3 URL:
# S3_PUBLIC_URL=https://sabarimala-yatra-media.s3.ap-south-1.amazonaws.com
# Only for MinIO / non-AWS S3:
# S3_ENDPOINT=http://localhost:9000
```

The AWS credentials can be reused from the existing Sanskar/other project — they
only need access to this one new bucket (see IAM policy below).

## One-time AWS setup

### 1. Create the bucket

```
aws s3api create-bucket \
  --bucket sabarimala-yatra-media \
  --region ap-south-1 \
  --create-bucket-configuration LocationConstraint=ap-south-1
```

Objects live under the `media/<trip_id>/<uuid>.<ext>` prefix.

### 2. CORS (needed for browser/Flutter-web `PUT`; harmless for mobile)

```json
[
  {
    "AllowedMethods": ["PUT", "GET"],
    "AllowedOrigins": ["*"],
    "AllowedHeaders": ["*"],
    "ExposeHeaders": ["ETag"],
    "MaxAgeSeconds": 3000
  }
]
```

```
aws s3api put-bucket-cors --bucket sabarimala-yatra-media --cors-configuration file://cors.json
```

### 3. Public read

**Recommended — CloudFront + Origin Access Control (OAC):** keep S3 Block Public
Access ON, create a CloudFront distribution with the bucket as origin using OAC,
and set `MEDIA_PUBLIC_BASE_URL` to the distribution domain. CloudFront reads
`media/*` privately from S3 and serves it publicly.

**Simplest — public bucket policy on the media prefix** (turn off Block Public
Access for the bucket first), then set `S3_PUBLIC_URL`:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "PublicReadMedia",
      "Effect": "Allow",
      "Principal": "*",
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::sabarimala-yatra-media/media/*"
    }
  ]
}
```

### 4. IAM permissions for the API credentials

The access key used by the API needs put/delete plus object-tagging on the
bucket (tagging is used for orphan cleanup — see below):

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:PutObject",
        "s3:PutObjectTagging",
        "s3:DeleteObject",
        "s3:DeleteObjectTagging"
      ],
      "Resource": "arn:aws:s3:::sabarimala-yatra-media/media/*"
    }
  ]
}
```

### 5. Lifecycle rule — expire orphaned (unconfirmed) uploads

Because uploads go straight to S3 *before* `POST /media/confirm`, a client that
crashes (or never confirms) leaves an object with no database row. To clean
these up precisely without touching real media:

- The presigned upload tags each object `state=unconfirmed`
  (`x-amz-tagging` is part of the signature; the client echoes it on the `PUT`).
- `POST /media/confirm` clears that tag (`DeleteObjectTagging`).
- A lifecycle rule expires objects **that still carry the tag** after 1 day.
  Confirmed objects (tag removed) are never touched.

`lifecycle.json`:

```json
{
  "Rules": [
    {
      "ID": "expire-unconfirmed-media",
      "Status": "Enabled",
      "Filter": {
        "And": {
          "Prefix": "media/",
          "Tags": [{ "Key": "state", "Value": "unconfirmed" }]
        }
      },
      "Expiration": { "Days": 1 }
    }
  ]
}
```

```
aws s3api put-bucket-lifecycle-configuration \
  --bucket sabarimala-yatra-media \
  --lifecycle-configuration file://lifecycle.json
```

> S3 lifecycle expiration runs once per day (UTC), so an orphan may live up to
> ~2 days. Raise `Days` if you want a wider safety margin; a confirmed object is
> already untagged and unaffected regardless.

## Notes

- If `DeleteObjectTagging` fails on confirm, the API logs a warning (the row is
  still saved). The object would then be a confirmed-but-still-tagged file that
  the lifecycle rule could expire — rare, but bump the lifecycle `Days` if you
  want extra headroom.
- Video is capped at 3 minutes on the client and 256 MB on the API's local/blob
  fallback path; direct-to-S3 uploads are limited only by S3.
- Allowed types: `image/jpeg|png|webp|gif|heic`, `video/mp4|quicktime|x-matroska|webm|3gpp`.
