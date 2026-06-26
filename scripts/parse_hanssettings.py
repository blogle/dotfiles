#!/usr/bin/env python3
"""
Fetch and parse hanssettings bouquet files from GitLab to generate M3U playlists.

Usage as module:
    from parse_hanssettings import fetch_and_generate_m3u
    fetch_and_generate_m3u(base_url, bouquet_files, output_path)

Usage as script:
    python3 parse_hanssettings.py [--output OUTPUT_PATH]
"""
import sys
import urllib.parse
import urllib.request
import argparse


# English-speaking bouquet files from hanssettings repo
BOUQUET_FILES = [
    # USA
    "userbouquet.stream_usa.tv",
    "userbouquet.stream_usa_new_york.radio",
    "userbouquet.stream_usa_texas.radio",
    "userbouquet.stream_usa.radio",
    # Canada
    "userbouquet.stream_canada.tv",
    "userbouquet.stream_canada.radio",
    # UK / England
    "userbouquet.stream_engeland.tv",
    "userbouquet.stream_samsung_engeland__uk_.tv",
    "userbouquet.stream_youtube___engeland__en_rest_uk_.tv",
    "userbouquet.stream_youtube___usa.tv",
    # AFN
    "userbouquet.stream_afn__american_forces_network_.radio",
    # Australia
    "userbouquet.stream_australi_.tv",
    "userbouquet.stream_australi_.radio",
    # New Zealand
    "userbouquet.stream_nieuw_zeeland.tv",
    "userbouquet.stream_nieuw_zeeland.radio",
    # Ireland
    "userbouquet.stream_ierland.tv",
    "userbouquet.stream_ierland.radio",
]

GITLAB_BASE = "https://gitlab.openpli.org/openpli/hanssettings/-/raw/master/e2_hanssettings_19e_23e"


def fetch_bouquet(url):
    """Fetch a single bouquet file from URL."""
    req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
    with urllib.request.urlopen(req, timeout=30) as response:
        return response.read().decode('utf-8')


def parse_bouquet(content):
    """Parse bouquet content and return list of (name, url) tuples."""
    channels = []

    for line in content.splitlines():
        line = line.strip()
        if not line or line.startswith('#NAME'):
            continue

        if line.startswith('#SERVICE'):
            parts = line.split(':', 10)
            if len(parts) >= 11:
                service_type = parts[0].split()[-1]
                if service_type in ('4097', '5002'):
                    url_with_name = parts[10]
                    url_with_name = urllib.parse.unquote(url_with_name)

                    if ':' in url_with_name:
                        last_colon = url_with_name.rfind(':')
                        if last_colon > 0:
                            url = url_with_name[:last_colon]
                            name = url_with_name[last_colon+1:]
                        else:
                            url = url_with_name
                            name = "Unknown"
                    else:
                        url = url_with_name
                        name = "Unknown"

                    if not name.startswith('++') and url:
                        channels.append((name, url))
    return channels


def fetch_and_generate_m3u(base_url=GITLAB_BASE, bouquet_files=None, output_path=None):
    """
    Fetch bouquet files from GitLab and generate M3U playlist.

    Args:
        base_url: Base URL for the bouquet files on GitLab
        bouquet_files: List of bouquet filenames to fetch
        output_path: Path to write M3U file (prints to stdout if None)

    Returns:
        List of (name, url) tuples
    """
    if bouquet_files is None:
        bouquet_files = BOUQUET_FILES

    all_channels = []
    seen = set()

    for bouquet_file in bouquet_files:
        url = f"{base_url}/{bouquet_file}"
        print(f"Fetching {bouquet_file}...", file=sys.stderr)

        try:
            content = fetch_bouquet(url)
            channels = parse_bouquet(content)
            print(f"  Parsed {len(channels)} channels", file=sys.stderr)

            for name, url in channels:
                key = (name.lower().strip(), url)
                if key not in seen:
                    seen.add(key)
                    all_channels.append((name, url))
        except Exception as e:
            print(f"  Error: {e}", file=sys.stderr)

    # Write M3U
    output = sys.stdout
    if output_path:
        output = open(output_path, 'w')

    with output:
        output.write("#EXTM3U\n")
        for name, url in all_channels:
            safe_name = name.replace(',', ';').strip()
            output.write(f"#EXTINF:-1,{safe_name}\n")
            output.write(f"{url}\n")

    if output_path:
        print(f"Generated {output_path} with {len(all_channels)} unique channels", file=sys.stderr)

    return all_channels


def main():
    parser = argparse.ArgumentParser(description="Generate English channels M3U from hanssettings")
    parser.add_argument('--base-url', default=GITLAB_BASE, help='Base GitLab URL')
    parser.add_argument('--output', '-o', help='Output M3U file path')
    args = parser.parse_args()

    fetch_and_generate_m3u(base_url=args.base_url, output_path=args.output)


if __name__ == "__main__":
    main()