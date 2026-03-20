#!/usr/bin/env python3
# frozen_string_literal: false

import json
import argparse
import sys

try:
    from camoufox.sync_api import Camoufox
except ImportError:
    print(json.dumps({"error": "camoufox not installed"}), file=sys.stderr)
    sys.exit(1)


def scrape_page(url, proxy=None):
    browser_args = {}
    if proxy:
        browser_args["proxy"] = {"server": proxy}

    with Camoufox(**browser_args) as browser:
        page = browser.new_page()
        page.goto(url, wait_until="networkidle", timeout=60000)

        content = page.content()

        title = page.title()

        scripts = page.evaluate("""
            (function() {
                try {
                    return document.title;
                } catch(e) {
                    return null;
                }
            })()
        """)

        return {
            "url": url,
            "title": title,
            "content_length": len(content),
            "html_preview": content[:5000] if content else None
        }


def main():
    parser = argparse.ArgumentParser(description="Generic scraper via Camoufox")
    parser.add_argument("url", help="URL to scrape")
    parser.add_argument("--proxy", default=None)
    parser.add_argument("--output", default=None, help="Output JSON file path")

    args = parser.parse_args()

    try:
        result = scrape_page(args.url, args.proxy)

        output_json = json.dumps(result, ensure_ascii=False)

        if args.output:
            with open(args.output, "w", encoding="utf-8") as f:
                f.write(output_json)
            print(json.dumps({"status": "ok", "output_file": args.output}))
        else:
            print(output_json)
    except Exception as e:
        print(json.dumps({"error": str(e)}), file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
