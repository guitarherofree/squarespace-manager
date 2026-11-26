#!/usr/bin/env python3
"""Sign a release archive with Sparkle's EdDSA (Ed25519) scheme and write appcast.xml.

The private key comes from the SPARKLE_ED_PRIVATE_KEY environment variable as base64:
either a 32-byte seed or a 64-byte seed-plus-public-key. The signature is checked against
the SUPublicEDKey inside the built app before anything is written, so a mismatched key
fails the release instead of shipping an update that installed copies would reject.
"""
import argparse
import base64
import email.utils
import html
import os
import plistlib
import sys
import time
from pathlib import Path


def fail(message):
    print(f"::error::{message}")
    sys.exit(1)


def load_private_key(text):
    from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey

    try:
        raw = base64.b64decode(text.strip(), validate=True)
    except Exception:
        fail("SPARKLE_ED_PRIVATE_KEY is not valid base64.")
    if len(raw) in (32, 64):
        return Ed25519PrivateKey.from_private_bytes(raw[:32])
    fail(f"SPARKLE_ED_PRIVATE_KEY decodes to {len(raw)} bytes; expected 32 or 64.")


def notes_to_html(markdown_text):
    try:
        import markdown

        return markdown.markdown(markdown_text)
    except ImportError:
        paragraphs = [p.strip() for p in markdown_text.split("\n\n") if p.strip()]
        return "\n".join(f"<p>{html.escape(p)}</p>" for p in paragraphs)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--archive", required=True, type=Path)
    parser.add_argument("--app", required=True, type=Path, help="Built .app, to read SUPublicEDKey")
    parser.add_argument("--version", required=True, help="Marketing version, e.g. 0.1.0")
    parser.add_argument("--build", required=True, help="CFBundleVersion of the build")
    parser.add_argument("--repo", required=True, help="owner/name on GitHub")
    parser.add_argument("--notes", type=Path, help="Markdown release notes")
    parser.add_argument("--min-system", default="14.0")
    parser.add_argument("--allow-unsigned", action="store_true",
                        help="Only for a first release, which no installed copy can update to.")
    parser.add_argument("--out", required=True, type=Path)
    args = parser.parse_args()

    data = args.archive.read_bytes()
    with open(args.app / "Contents" / "Info.plist", "rb") as handle:
        info = plistlib.load(handle)
    public_key_b64 = info.get("SUPublicEDKey")
    if not public_key_b64:
        fail("The built app has no SUPublicEDKey.")
    if info.get("CFBundleVersion") != args.build:
        fail(f"App build {info.get('CFBundleVersion')} doesn't match --build {args.build}.")

    signature_attr = ""
    private_key_text = os.environ.get("SPARKLE_ED_PRIVATE_KEY", "").strip()
    if private_key_text:
        from cryptography.exceptions import InvalidSignature
        from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PublicKey

        private_key = load_private_key(private_key_text)
        signature = private_key.sign(data)
        public_key = Ed25519PublicKey.from_public_bytes(base64.b64decode(public_key_b64))
        try:
            public_key.verify(signature, data)
        except InvalidSignature:
            fail("SPARKLE_ED_PRIVATE_KEY doesn't match the app's SUPublicEDKey.")
        signature_attr = f' sparkle:edSignature="{base64.b64encode(signature).decode()}"'
        print("Signed the archive; signature verified against SUPublicEDKey.")
    elif args.allow_unsigned:
        print("::warning::No SPARKLE_ED_PRIVATE_KEY. Publishing the first release unsigned; add the secret before the next release.")
    else:
        fail("SPARKLE_ED_PRIVATE_KEY is missing. Add it under Settings > Secrets and variables > Actions.")

    url = f"https://github.com/{args.repo}/releases/download/v{args.version}/{args.archive.name}"
    notes_html = notes_to_html(args.notes.read_text()) if args.notes and args.notes.exists() else ""
    pub_date = email.utils.formatdate(time.time(), usegmt=True)

    appcast = f"""<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
  <channel>
    <title>Squarespace Manager</title>
    <link>https://github.com/{args.repo}</link>
    <description>Updates for Squarespace Manager</description>
    <language>en</language>
    <item>
      <title>Version {html.escape(args.version)}</title>
      <pubDate>{pub_date}</pubDate>
      <sparkle:version>{html.escape(args.build)}</sparkle:version>
      <sparkle:shortVersionString>{html.escape(args.version)}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>{html.escape(args.min_system)}</sparkle:minimumSystemVersion>
      <description><![CDATA[{notes_html}]]></description>
      <enclosure url="{html.escape(url)}" length="{len(data)}" type="application/octet-stream"{signature_attr}/>
    </item>
  </channel>
</rss>
"""
    args.out.write_text(appcast)
    print(f"Wrote {args.out} for {args.version} (build {args.build}), {len(data)} bytes.")


if __name__ == "__main__":
    main()
