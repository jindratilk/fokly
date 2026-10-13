"""Adds (or replaces) one release in site/appcast.xml, the feed Sparkle reads from fokly.app.

Usage: python3 scripts/appcast.py <app> <dmg> <ed-signature> <notes.html>
The enclosure points at the versioned asset of the GitHub release (vX.Y/Fokly-X.Y.dmg), so
update downloads are counted apart from website downloads (Fokly.dmg).
"""
import os, plistlib, re, sys
from email.utils import formatdate

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FEED = os.path.join(ROOT, "site/appcast.xml")
app, dmg, signature, notes = sys.argv[1:5]

info = plistlib.load(open(os.path.join(app, "Contents/Info.plist"), "rb"))
version, build = info["CFBundleShortVersionString"], info["CFBundleVersion"]
url = f"https://github.com/jindratilk/fokly/releases/download/v{version}/Fokly-{version}.dmg"
item = f"""    <item>
      <title>Fokly {version}</title>
      <pubDate>{formatdate(usegmt=True)}</pubDate>
      <sparkle:version>{build}</sparkle:version>
      <sparkle:shortVersionString>{version}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>{info.get("LSMinimumSystemVersion", "26.0")}</sparkle:minimumSystemVersion>
      <description><![CDATA[
{open(notes).read().strip()}
      ]]></description>
      <enclosure url="{url}" length="{os.path.getsize(dmg)}" type="application/octet-stream" sparkle:edSignature="{signature}"/>
    </item>
"""

if os.path.exists(FEED):
    feed = open(FEED).read()
    feed = re.sub(rf"    <item>\n      <title>Fokly {re.escape(version)}</title>.*?    </item>\n", "", feed, flags=re.S)
else:
    feed = """<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Fokly</title>
    <link>https://fokly.app</link>
    <description>Fokly updates</description>
    <language>en</language>
  </channel>
</rss>
"""
feed = feed.replace("    <language>en</language>\n", "    <language>en</language>\n" + item, 1)
open(FEED, "w").write(feed)
print(f"appcast: Fokly {version} ({build}) → {url}")
