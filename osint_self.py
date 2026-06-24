#!/usr/bin/env python3
"""
osint_self.py — Personal OSINT Footprint Tool
Self-recon: understand your own digital exposure across breaches, data brokers,
paste sites, social platforms, and code repositories.
"""

import asyncio
import json
import os
import random
import re
import sys
import time
import argparse
import base64
import subprocess
import importlib.util
import urllib.parse
from datetime import datetime
from pathlib import Path
from typing import Any

# ── Dependency check ──────────────────────────────────────────────────────────

REQUIRED_PACKAGES = {
    "aiohttp":     "aiohttp",
    "bs4":         "beautifulsoup4",
    "playwright":  "playwright",
    "rich":        "rich",
}

OPTIONAL_PACKAGES = {
    "holehe":      "holehe",
    "sherlock":    "sherlock-project",
}

def check_dependencies(dry_run: bool = False) -> bool:
    missing_required = []
    missing_optional = []

    for mod, pkg in REQUIRED_PACKAGES.items():
        if importlib.util.find_spec(mod) is None:
            missing_required.append(pkg)

    for mod, pkg in OPTIONAL_PACKAGES.items():
        if importlib.util.find_spec(mod) is None:
            missing_optional.append(pkg)

    if missing_required or missing_optional:
        print("\n[DEPENDENCY CHECK]")
        if missing_required:
            print(f"  Missing required: {', '.join(missing_required)}")
        if missing_optional:
            print(f"  Missing optional: {', '.join(missing_optional)} (some modules will be skipped)")

        if missing_required:
            ans = input("\nInstall missing required packages now? [Y/n] ").strip().lower()
            if ans in ("", "y", "yes"):
                if dry_run:
                    print("  [dry-run] Would run: pip install " + " ".join(missing_required))
                else:
                    subprocess.check_call([sys.executable, "-m", "pip", "install"] + missing_required)
            else:
                print("Cannot continue without required packages.")
                return False

        if missing_optional and not dry_run:
            ans = input(f"Install optional packages ({', '.join(missing_optional)})? [y/N] ").strip().lower()
            if ans in ("y", "yes"):
                subprocess.check_call([sys.executable, "-m", "pip", "install"] + missing_optional)

        # After install, check playwright browsers
        try:
            import playwright  # noqa: F401
            result = subprocess.run(
                ["python3", "-m", "playwright", "install", "chromium", "--with-deps"],
                capture_output=True, text=True
            )
            if result.returncode != 0 and not dry_run:
                print("  Warning: Playwright browser install may have failed. Run manually:")
                print("    playwright install chromium --with-deps")
        except Exception:
            pass

    else:
        print("[✓] All required dependencies present.")

    return True


# ── User-agent rotation ───────────────────────────────────────────────────────

USER_AGENTS = [
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/123.0.0.0 Safari/537.36",
    "Mozilla/5.0 (X11; Linux x86_64; rv:125.0) Gecko/20100101 Firefox/125.0",
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15",
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:124.0) Gecko/20100101 Firefox/124.0",
]

def random_ua() -> str:
    return random.choice(USER_AGENTS)

async def jitter(min_s: float = 2.0, max_s: float = 5.0):
    await asyncio.sleep(random.uniform(min_s, max_s))


# ── Finding data model ────────────────────────────────────────────────────────

SEVERITY_ORDER = {"Critical": 0, "High": 1, "Medium": 2, "Low": 3, "Info": 4}

class Finding:
    def __init__(self, module: str, identifier: str, title: str, detail: str,
                 severity: str = "Info", url: str = "", raw: Any = None):
        self.module = module
        self.identifier = identifier
        self.title = title
        self.detail = detail
        self.severity = severity
        self.url = url
        self.raw = raw
        self.timestamp = datetime.utcnow().isoformat()

    def to_dict(self) -> dict:
        return {
            "module": self.module,
            "identifier": self.identifier,
            "title": self.title,
            "detail": self.detail,
            "severity": self.severity,
            "url": self.url,
            "raw": self.raw,
            "timestamp": self.timestamp,
        }


# ── Interactive prompt ────────────────────────────────────────────────────────

def prompt_identifiers() -> dict:
    print("\n" + "═" * 60)
    print("  OSINT SELF-RECON — Enter your identifiers")
    print("═" * 60)
    print("(Press Enter to skip any field, comma-separate multiple values)\n")

    def ask(label: str, example: str = "") -> list[str]:
        hint = f"  e.g. {example}" if example else ""
        val = input(f"  {label}{hint}\n  > ").strip()
        if not val:
            return []
        return [v.strip() for v in val.split(",") if v.strip()]

    names = ask("Full name + variations", "John Smith, John A Smith, JA Smith")
    emails = ask("Email addresses", "john@gmail.com, john@work.com")
    phones = ask("Phone numbers (AU)", "0412 345 678, +61412345678")
    usernames = ask("Usernames / handles", "jsmith, johnsmith99")
    suburb_raw = ask("Suburb + State", "Bondi, NSW")
    suburb = suburb_raw[0] if suburb_raw else ""

    # Normalise phones
    phones_norm = []
    for p in phones:
        p2 = re.sub(r"[\s\-()]", "", p)
        phones_norm.append(p2)
        if p2.startswith("0"):
            phones_norm.append("+61" + p2[1:])
        elif p2.startswith("+61"):
            phones_norm.append("0" + p2[3:])

    return {
        "names": names,
        "emails": emails,
        "phones": list(dict.fromkeys(phones_norm)),
        "usernames": usernames,
        "suburb": suburb,
    }


# ── Module 1: Google Dorks ────────────────────────────────────────────────────

async def module_google_dorks(identifiers: dict) -> list[Finding]:
    findings = []
    all_ids = identifiers["names"] + identifiers["emails"] + identifiers["usernames"]
    suburb = identifiers.get("suburb", "")

    dork_templates = [
        'site:pastebin.com "{id}"',
        'site:github.com "{id}"',
        '"{id}" filetype:sql OR filetype:csv OR filetype:txt',
        '"{id}" inurl:leak OR inurl:dump',
        '"{id}" inurl:breach',
        'site:rentry.co "{id}"',
        'site:controlc.com "{id}"',
    ]

    name_suburb_dorks = []
    for name in identifiers["names"]:
        if suburb:
            name_suburb_dorks.append(f'"{name}" "{suburb}" site:au')
            name_suburb_dorks.append(f'"{name}" "{suburb}"')

    base = "https://www.google.com/search?q="

    for id_val in all_ids:
        for tmpl in dork_templates:
            query = tmpl.format(id=id_val)
            url = base + urllib.parse.quote(query)
            findings.append(Finding(
                module="Google Dorks",
                identifier=id_val,
                title=f"Dork: {query[:80]}",
                detail=f"Manual review required. Open URL to inspect results.",
                severity="Info",
                url=url,
                raw={"query": query, "url": url}
            ))

    for dork in name_suburb_dorks:
        url = base + urllib.parse.quote(dork)
        findings.append(Finding(
            module="Google Dorks",
            identifier=identifiers["names"][0] if identifiers["names"] else "name",
            title=f"Dork: {dork[:80]}",
            detail="Name + suburb correlation dork. Manual review required.",
            severity="Info",
            url=url,
            raw={"query": dork, "url": url}
        ))

    print(f"  [Dorks] Generated {len(findings)} dork URLs for manual review.")
    return findings


# ── Module 2: Data Broker Enumeration ─────────────────────────────────────────

DATA_BROKERS = [
    {
        "name": "Whitepages AU",
        "url_tmpl": "https://www.whitepages.com.au/residential/?type=people&name={name}&suburb={suburb}",
        "optout": "https://www.whitepages.com.au/optout",
    },
    {
        "name": "Spokeo",
        "url_tmpl": "https://www.spokeo.com/{name_slug}",
        "optout": "https://www.spokeo.com/optout",
    },
    {
        "name": "BeenVerified",
        "url_tmpl": "https://www.beenverified.com/people-search/",
        "optout": "https://www.beenverified.com/app/optout/search",
    },
    {
        "name": "Intelius",
        "url_tmpl": "https://www.intelius.com/people-search/",
        "optout": "https://www.intelius.com/opt-out",
    },
    {
        "name": "FastPeopleSearch",
        "url_tmpl": "https://www.fastpeoplesearch.com/name/{name_slug}",
        "optout": "https://www.fastpeoplesearch.com/removal",
    },
    {
        "name": "PeopleFinder",
        "url_tmpl": "https://www.peoplefinder.com/people/{name_slug}/",
        "optout": "https://www.peoplefinder.com/opt-out.php",
    },
    {
        "name": "TruePeopleSearch",
        "url_tmpl": "https://www.truepeoplesearch.com/results?name={name_encoded}",
        "optout": "https://www.truepeoplesearch.com/removal",
    },
    {
        "name": "ZabaSearch",
        "url_tmpl": "https://www.zabasearch.com/people/{name_slug}/",
        "optout": "https://www.zabasearch.com/privacy.php",
    },
]

async def module_data_brokers(identifiers: dict) -> list[Finding]:
    findings = []
    screenshots_dir = Path("osint_screenshots")
    screenshots_dir.mkdir(exist_ok=True)

    primary_name = identifiers["names"][0] if identifiers["names"] else ""
    suburb = identifiers.get("suburb", "")

    if not primary_name:
        print("  [DataBrokers] No name provided, skipping.")
        return findings

    try:
        from playwright.async_api import async_playwright
    except ImportError:
        print("  [DataBrokers] Playwright not available, skipping.")
        return findings

    name_slug = re.sub(r"\s+", "-", primary_name.lower())
    name_encoded = urllib.parse.quote(primary_name)
    suburb_encoded = urllib.parse.quote(suburb)

    async with async_playwright() as pw:
        browser = await pw.chromium.launch(headless=True)
        context = await browser.new_context(
            user_agent=random_ua(),
            viewport={"width": 1280, "height": 900},
        )

        for broker in DATA_BROKERS:
            try:
                url = broker["url_tmpl"].format(
                    name=primary_name,
                    name_slug=name_slug,
                    name_encoded=name_encoded,
                    suburb=suburb_encoded,
                )
                print(f"  [DataBrokers] Checking {broker['name']}...")
                page = await context.new_page()
                await page.goto(url, timeout=30000, wait_until="domcontentloaded")
                await jitter(2, 4)

                # Screenshot
                safe_name = re.sub(r"[^\w]", "_", broker["name"])
                ss_path = str(screenshots_dir / f"{safe_name}.png")
                await page.screenshot(path=ss_path, full_page=True)

                # Try to detect if results are present
                content = await page.content()
                has_result = any(kw in content.lower() for kw in [
                    primary_name.lower().split()[0],
                    "result", "found", "record", "people", "listing"
                ])

                severity = "High" if has_result else "Info"
                detail = (
                    f"Potential listing found. Screenshot saved: {ss_path}. Opt-out: {broker['optout']}"
                    if has_result else
                    f"No obvious listing detected. Screenshot saved: {ss_path}"
                )

                findings.append(Finding(
                    module="Data Brokers",
                    identifier=primary_name,
                    title=f"{broker['name']} — {'Possible listing' if has_result else 'No match detected'}",
                    detail=detail,
                    severity=severity,
                    url=url,
                    raw={"broker": broker["name"], "optout": broker["optout"],
                         "screenshot": ss_path, "has_result": has_result}
                ))

                await page.close()

            except Exception as e:
                print(f"  [DataBrokers] Error on {broker['name']}: {e}")
                findings.append(Finding(
                    module="Data Brokers",
                    identifier=primary_name,
                    title=f"{broker['name']} — Error",
                    detail=str(e),
                    severity="Info",
                    url=broker.get("url_tmpl", ""),
                    raw={"error": str(e)}
                ))
            await jitter()

        await browser.close()

    return findings


# ── Module 3: Username Enumeration (Sherlock) ─────────────────────────────────

async def module_username_enum(identifiers: dict) -> list[Finding]:
    findings = []
    usernames = identifiers.get("usernames", [])
    if not usernames:
        print("  [Sherlock] No usernames provided, skipping.")
        return findings

    if importlib.util.find_spec("sherlock") is None:
        print("  [Sherlock] sherlock-project not installed, skipping.")
        return findings

    for username in usernames:
        print(f"  [Sherlock] Checking username: {username}")
        try:
            result = subprocess.run(
                [sys.executable, "-m", "sherlock", username, "--print-found", "--timeout", "10"],
                capture_output=True, text=True, timeout=300
            )
            output = result.stdout

            hits = []
            for line in output.splitlines():
                if line.startswith("[+]"):
                    # Extract URL from sherlock output
                    parts = line.split(": ", 1)
                    if len(parts) == 2:
                        hits.append(parts[1].strip())

            if hits:
                findings.append(Finding(
                    module="Username Enum",
                    identifier=username,
                    title=f"Username '{username}' found on {len(hits)} platform(s)",
                    detail="\n".join(hits[:20]) + (f"\n... and {len(hits)-20} more" if len(hits) > 20 else ""),
                    severity="Medium",
                    url=hits[0] if hits else "",
                    raw={"username": username, "hits": hits}
                ))
            else:
                findings.append(Finding(
                    module="Username Enum",
                    identifier=username,
                    title=f"Username '{username}' — no hits",
                    detail="No public profiles found.",
                    severity="Info",
                    url="",
                    raw={"username": username, "hits": []}
                ))
        except Exception as e:
            print(f"  [Sherlock] Error for {username}: {e}")

    return findings


# ── Module 4: Email Recon ─────────────────────────────────────────────────────

async def module_email_recon(identifiers: dict, session) -> list[Finding]:
    findings = []
    emails = identifiers.get("emails", [])
    if not emails:
        return findings

    # 4a. Holehe
    if importlib.util.find_spec("holehe") is not None:
        for email in emails:
            print(f"  [Holehe] Checking {email}...")
            try:
                result = subprocess.run(
                    [sys.executable, "-m", "holehe", email, "--only-used"],
                    capture_output=True, text=True, timeout=180
                )
                hits = []
                for line in result.stdout.splitlines():
                    if "[+]" in line:
                        hits.append(line.strip())

                if hits:
                    findings.append(Finding(
                        module="Email Recon",
                        identifier=email,
                        title=f"Holehe: {email} registered on {len(hits)} service(s)",
                        detail="\n".join(hits),
                        severity="Medium",
                        url="",
                        raw={"email": email, "hits": hits}
                    ))
            except Exception as e:
                print(f"  [Holehe] Error: {e}")
    else:
        print("  [Holehe] Not installed, skipping.")

    # 4b. Epieos free API
    for email in emails:
        await jitter(2, 4)
        try:
            url = f"https://epieos.com/api/email/{urllib.parse.quote(email)}"
            headers = {"User-Agent": random_ua(), "Accept": "application/json"}
            async with session.get(url, headers=headers, timeout=15) as resp:
                if resp.status == 200:
                    data = await resp.json(content_type=None)
                    if data:
                        findings.append(Finding(
                            module="Email Recon",
                            identifier=email,
                            title=f"Epieos: data found for {email}",
                            detail=json.dumps(data, indent=2)[:500],
                            severity="High",
                            url=f"https://epieos.com/?q={urllib.parse.quote(email)}&type=email",
                            raw=data
                        ))
        except Exception as e:
            print(f"  [Epieos] Error for {email}: {e}")

    # 4c. DeHashed (if API key set)
    dehashed_key = os.environ.get("DEHASHED_API_KEY", "")
    dehashed_email = os.environ.get("DEHASHED_EMAIL", "")
    if dehashed_key and dehashed_email:
        for email in emails:
            await jitter()
            try:
                auth = base64.b64encode(f"{dehashed_email}:{dehashed_key}".encode()).decode()
                headers = {
                    "Authorization": f"Basic {auth}",
                    "Accept": "application/json",
                    "User-Agent": random_ua(),
                }
                url = f"https://api.dehashed.com/search?query=email%3A{urllib.parse.quote(email)}&size=10"
                async with session.get(url, headers=headers, timeout=15) as resp:
                    if resp.status == 200:
                        data = await resp.json(content_type=None)
                        entries = data.get("entries", []) or []
                        if entries:
                            has_pw = any(e.get("password") for e in entries)
                            findings.append(Finding(
                                module="Email Recon",
                                identifier=email,
                                title=f"DeHashed: {len(entries)} breach record(s) for {email}",
                                detail=f"Password fields present: {has_pw}. Check DeHashed dashboard.",
                                severity="Critical" if has_pw else "High",
                                url="https://dehashed.com/",
                                raw={"count": len(entries), "has_password": has_pw}
                            ))
            except Exception as e:
                print(f"  [DeHashed] Error: {e}")
    else:
        print("  [DeHashed] DEHASHED_API_KEY/DEHASHED_EMAIL not set, skipping.")

    return findings


# ── Module 5: Phone Recon ─────────────────────────────────────────────────────

async def module_phone_recon(identifiers: dict, session) -> list[Finding]:
    findings = []
    phones = identifiers.get("phones", [])
    if not phones:
        return findings

    unique_phones = list(dict.fromkeys(phones))

    for phone in unique_phones:
        await jitter()

        # NumVerify (free tier, 100/month, no key required for basic)
        numverify_key = os.environ.get("NUMVERIFY_API_KEY", "")
        if numverify_key:
            try:
                url = f"http://apilayer.net/api/validate?access_key={numverify_key}&number={urllib.parse.quote(phone)}&country_code=AU"
                async with session.get(url, timeout=10) as resp:
                    if resp.status == 200:
                        data = await resp.json(content_type=None)
                        if data.get("valid"):
                            findings.append(Finding(
                                module="Phone Recon",
                                identifier=phone,
                                title=f"NumVerify: {phone} — {data.get('line_type', 'unknown')} ({data.get('carrier', 'unknown')})",
                                detail=json.dumps(data, indent=2),
                                severity="Medium",
                                url="",
                                raw=data
                            ))
            except Exception as e:
                print(f"  [NumVerify] Error: {e}")
        else:
            print("  [NumVerify] NUMVERIFY_API_KEY not set, skipping carrier lookup.")

        # Truecaller public search (best-effort scrape)
        try:
            tc_url = f"https://www.truecaller.com/search/au/{urllib.parse.quote(phone)}"
            headers = {"User-Agent": random_ua()}
            async with session.get(tc_url, headers=headers, timeout=15, allow_redirects=True) as resp:
                text = await resp.text()
                # Truecaller often requires JS — note if page has name data
                if phone.replace("+61", "").replace("0", "", 1)[:3] in text:
                    findings.append(Finding(
                        module="Phone Recon",
                        identifier=phone,
                        title=f"Truecaller: possible data for {phone}",
                        detail="Truecaller page loaded — manual review recommended (JS may be required).",
                        severity="Medium",
                        url=tc_url,
                        raw={"url": tc_url}
                    ))
        except Exception as e:
            print(f"  [Truecaller] Error: {e}")

    return findings


# ── Module 6: Breach / Paste Data ─────────────────────────────────────────────

async def module_breach_paste(identifiers: dict, session) -> list[Finding]:
    findings = []
    all_ids = (identifiers["names"] + identifiers["emails"] +
               identifiers["usernames"] + identifiers["phones"])

    # Pastebin search (public)
    for id_val in all_ids[:5]:  # Rate limit
        await jitter(3, 6)
        try:
            url = f"https://pastebin.com/search?q={urllib.parse.quote(id_val)}"
            headers = {"User-Agent": random_ua()}
            async with session.get(url, headers=headers, timeout=15) as resp:
                if resp.status == 200:
                    text = await resp.text()
                    from bs4 import BeautifulSoup
                    soup = BeautifulSoup(text, "html.parser")
                    results = soup.select(".gsc-result")
                    if results:
                        findings.append(Finding(
                            module="Breach/Paste",
                            identifier=id_val,
                            title=f"Pastebin: {len(results)} result(s) for '{id_val}'",
                            detail=f"Review manually: {url}",
                            severity="High",
                            url=url,
                            raw={"count": len(results)}
                        ))
        except Exception as e:
            print(f"  [Pastebin] Error: {e}")

    # IntelligenceX free API
    intelx_key = os.environ.get("INTELX_API_KEY", "")
    if intelx_key:
        for id_val in all_ids[:3]:
            await jitter()
            try:
                # Search
                search_url = "https://2.intelx.io/intelligent/search"
                payload = {"term": id_val, "maxresults": 10, "media": 0, "sort": 4, "terminate": []}
                headers = {"x-key": intelx_key, "Content-Type": "application/json", "User-Agent": random_ua()}
                async with session.post(search_url, json=payload, headers=headers, timeout=15) as resp:
                    if resp.status == 200:
                        data = await resp.json(content_type=None)
                        search_id = data.get("id", "")
                        if search_id:
                            await asyncio.sleep(3)
                            result_url = f"https://2.intelx.io/intelligent/search/result?id={search_id}&limit=10"
                            async with session.get(result_url, headers=headers, timeout=15) as r2:
                                if r2.status == 200:
                                    rdata = await r2.json(content_type=None)
                                    records = rdata.get("records", []) or []
                                    if records:
                                        findings.append(Finding(
                                            module="Breach/Paste",
                                            identifier=id_val,
                                            title=f"IntelligenceX: {len(records)} record(s) for '{id_val}'",
                                            detail="Review IntelligenceX dashboard.",
                                            severity="High",
                                            url="https://intelx.io/",
                                            raw={"count": len(records)}
                                        ))
            except Exception as e:
                print(f"  [IntelX] Error: {e}")
    else:
        print("  [IntelX] INTELX_API_KEY not set, skipping.")

    # LeakCheck.io
    leakcheck_key = os.environ.get("LEAKCHECK_API_KEY", "")
    if leakcheck_key:
        for email in identifiers["emails"][:3]:
            await jitter()
            try:
                url = f"https://leakcheck.io/api/public?key={leakcheck_key}&check={urllib.parse.quote(email)}&type=email"
                headers = {"User-Agent": random_ua()}
                async with session.get(url, headers=headers, timeout=15) as resp:
                    if resp.status == 200:
                        data = await resp.json(content_type=None)
                        if data.get("found") and data.get("sources"):
                            findings.append(Finding(
                                module="Breach/Paste",
                                identifier=email,
                                title=f"LeakCheck: {email} in {len(data['sources'])} breach(es)",
                                detail=", ".join(s.get("name", "") for s in data["sources"][:10]),
                                severity="Critical",
                                url="https://leakcheck.io/",
                                raw=data
                            ))
            except Exception as e:
                print(f"  [LeakCheck] Error: {e}")
    else:
        print("  [LeakCheck] LEAKCHECK_API_KEY not set, skipping.")

    return findings


# ── Module 7: GitHub / Code Leak ──────────────────────────────────────────────

async def module_github_search(identifiers: dict, session) -> list[Finding]:
    findings = []
    gh_token = os.environ.get("GITHUB_TOKEN", "")
    headers = {"User-Agent": random_ua(), "Accept": "application/vnd.github.v3.text-match+json"}
    if gh_token:
        headers["Authorization"] = f"token {gh_token}"

    search_terms = identifiers["emails"] + identifiers["usernames"]
    base_url = "https://api.github.com/search/code"

    for term in search_terms[:5]:
        await jitter(3, 6)
        try:
            params = {"q": term, "per_page": 10}
            async with session.get(base_url, headers=headers, params=params, timeout=15) as resp:
                if resp.status == 200:
                    data = await resp.json(content_type=None)
                    items = data.get("items", [])
                    if items:
                        urls = [i["html_url"] for i in items[:5]]
                        findings.append(Finding(
                            module="GitHub/Code Leak",
                            identifier=term,
                            title=f"GitHub: '{term}' found in {data.get('total_count', len(items))} file(s)",
                            detail="\n".join(urls),
                            severity="High",
                            url=urls[0] if urls else "",
                            raw={"total_count": data.get("total_count"), "urls": urls}
                        ))
                elif resp.status == 403:
                    print(f"  [GitHub] Rate limited. Set GITHUB_TOKEN env var for higher limits.")
                    break
        except Exception as e:
            print(f"  [GitHub] Error for '{term}': {e}")

    return findings


# ── Module 8: Domain / WHOIS / crt.sh ────────────────────────────────────────

async def module_domain_crt(identifiers: dict, session) -> list[Finding]:
    findings = []

    for email in identifiers["emails"]:
        await jitter()
        try:
            domain = email.split("@")[-1] if "@" in email else ""
            # crt.sh — search by email identity
            url = f"https://crt.sh/?q={urllib.parse.quote(email)}&output=json"
            headers = {"User-Agent": random_ua(), "Accept": "application/json"}
            async with session.get(url, headers=headers, timeout=20) as resp:
                if resp.status == 200:
                    text = await resp.text()
                    try:
                        data = json.loads(text)
                        if data:
                            domains_found = list({d.get("common_name", "") for d in data if d.get("common_name")})
                            findings.append(Finding(
                                module="Domain/WHOIS",
                                identifier=email,
                                title=f"crt.sh: {len(data)} certificate(s) linked to {email}",
                                detail="Domains: " + ", ".join(domains_found[:10]),
                                severity="Low",
                                url=f"https://crt.sh/?q={urllib.parse.quote(email)}",
                                raw={"count": len(data), "domains": domains_found}
                            ))
                    except json.JSONDecodeError:
                        pass
        except Exception as e:
            print(f"  [crt.sh] Error for {email}: {e}")

        # Also check domain cert history
        if "@" in email:
            domain = email.split("@")[1]
            await jitter()
            try:
                url = f"https://crt.sh/?q=%.{domain}&output=json"
                async with session.get(url, headers={"User-Agent": random_ua()}, timeout=20) as resp:
                    if resp.status == 200:
                        text = await resp.text()
                        try:
                            data = json.loads(text)
                            if len(data) > 0:
                                findings.append(Finding(
                                    module="Domain/WHOIS",
                                    identifier=domain,
                                    title=f"crt.sh: {len(data)} certificate(s) for *.{domain}",
                                    detail="Domain has issued certificates — may indicate ownership.",
                                    severity="Low",
                                    url=f"https://crt.sh/?q=%.{domain}",
                                    raw={"count": len(data)}
                                ))
                        except json.JSONDecodeError:
                            pass
            except Exception as e:
                print(f"  [crt.sh domain] Error: {e}")

    return findings


# ── Module 9: Dark Web Index (Ahmia) ─────────────────────────────────────────

async def module_darkweb_ahmia(identifiers: dict, session) -> list[Finding]:
    findings = []
    all_ids = identifiers["emails"] + identifiers["usernames"] + identifiers["names"][:2]

    for id_val in all_ids[:4]:
        await jitter(3, 6)
        try:
            url = f"https://ahmia.fi/search/?q={urllib.parse.quote(id_val)}"
            headers = {"User-Agent": random_ua()}
            async with session.get(url, headers=headers, timeout=20) as resp:
                if resp.status == 200:
                    text = await resp.text()
                    from bs4 import BeautifulSoup
                    soup = BeautifulSoup(text, "html.parser")
                    results = soup.select(".result") or soup.select("li.result")
                    if results:
                        findings.append(Finding(
                            module="Dark Web Index",
                            identifier=id_val,
                            title=f"Ahmia.fi: {len(results)} Tor-indexed result(s) for '{id_val}'",
                            detail="Results indexed from Tor hidden services. Manual review at Ahmia.fi recommended.",
                            severity="High",
                            url=url,
                            raw={"count": len(results), "query": id_val}
                        ))
                    else:
                        findings.append(Finding(
                            module="Dark Web Index",
                            identifier=id_val,
                            title=f"Ahmia.fi: no results for '{id_val}'",
                            detail="No Tor-indexed results found.",
                            severity="Info",
                            url=url,
                            raw={"count": 0}
                        ))
        except Exception as e:
            print(f"  [Ahmia] Error for '{id_val}': {e}")

    return findings


# ── Module 10: Social Presence ────────────────────────────────────────────────

SOCIAL_PLATFORMS = [
    {
        "name": "LinkedIn",
        "url_tmpl": "https://www.linkedin.com/search/results/people/?keywords={name_encoded}",
        "username_tmpl": "https://www.linkedin.com/in/{username}",
    },
    {
        "name": "Facebook",
        "url_tmpl": "https://www.facebook.com/search/people/?q={name_encoded}",
        "username_tmpl": "https://www.facebook.com/{username}",
    },
    {
        "name": "Instagram",
        "url_tmpl": "https://www.instagram.com/{username}/",
        "username_tmpl": "https://www.instagram.com/{username}/",
    },
    {
        "name": "X / Twitter",
        "url_tmpl": "https://x.com/search?q={name_encoded}&f=user",
        "username_tmpl": "https://x.com/{username}",
    },
]

async def module_social_presence(identifiers: dict, session) -> list[Finding]:
    findings = []
    names = identifiers.get("names", [])
    usernames = identifiers.get("usernames", [])

    for platform in SOCIAL_PLATFORMS:
        # Name search dork URLs (for manual review — most require login)
        for name in names[:2]:
            name_encoded = urllib.parse.quote(name)
            url = platform["url_tmpl"].format(name_encoded=name_encoded, username="")
            findings.append(Finding(
                module="Social Presence",
                identifier=name,
                title=f"{platform['name']}: search URL for '{name}'",
                detail="Manual review required — most social searches require login.",
                severity="Info",
                url=url,
                raw={"platform": platform["name"], "type": "name_search"}
            ))

        # Direct username profile checks
        for username in usernames:
            await jitter(1, 3)
            url = platform["username_tmpl"].format(username=username, name_encoded=urllib.parse.quote(username))
            try:
                headers = {"User-Agent": random_ua()}
                async with session.get(url, headers=headers, timeout=15, allow_redirects=True) as resp:
                    exists = resp.status == 200
                    if exists:
                        # Crude check: avoid false positives from login-redirect pages
                        text = await resp.text()
                        redirected_to_login = any(k in text.lower() for k in [
                            "log in to", "sign in to", "create an account", "join linkedin"
                        ])
                        if not redirected_to_login:
                            findings.append(Finding(
                                module="Social Presence",
                                identifier=username,
                                title=f"{platform['name']}: profile possibly exists for @{username}",
                                detail=f"HTTP 200 at {url}",
                                severity="Medium",
                                url=url,
                                raw={"platform": platform["name"], "username": username, "status": resp.status}
                            ))
            except Exception as e:
                print(f"  [Social] Error checking {platform['name']} for {username}: {e}")

    return findings


# ── HTML Report Generator ─────────────────────────────────────────────────────

def generate_html_report(findings: list[Finding], identifiers: dict) -> str:
    findings_json = json.dumps([f.to_dict() for f in findings], indent=2, default=str)

    severity_counts = {"Critical": 0, "High": 0, "Medium": 0, "Low": 0, "Info": 0}
    for f in findings:
        severity_counts[f.severity] = severity_counts.get(f.severity, 0) + 1

    # Build remediation list from data broker findings
    broker_findings = [f for f in findings if f.module == "Data Brokers" and f.severity == "High"]
    remediation_rows = ""
    for bf in broker_findings:
        raw = bf.raw or {}
        optout = raw.get("optout", "")
        broker = raw.get("broker", bf.title)
        remediation_rows += f"""
        <tr>
            <td><span class="badge badge-high">High</span></td>
            <td>{broker}</td>
            <td><a href="{optout}" target="_blank">Opt-out page</a></td>
            <td>Submit removal request at opt-out URL. Allow 30-90 days.</td>
        </tr>"""

    breach_findings = [f for f in findings if f.severity in ("Critical", "High") and f.module in ("Email Recon", "Breach/Paste")]
    for bf in breach_findings:
        remediation_rows += f"""
        <tr>
            <td><span class="badge badge-{'critical' if bf.severity=='Critical' else 'high'}">{bf.severity}</span></td>
            <td>{bf.module}: {bf.identifier}</td>
            <td><a href="{bf.url}" target="_blank">View</a></td>
            <td>Change passwords for all accounts using this credential. Enable MFA. Consider password manager.</td>
        </tr>"""

    optout_email_template = """To: privacy@[databroker.com]
Subject: Personal Data Removal Request

Dear Privacy Team,

I am writing to request the removal of my personal information from your database
in accordance with applicable privacy laws (Australian Privacy Act 1988 / GDPR / CCPA).

Full Name: [YOUR NAME]
Email: [YOUR EMAIL]
Phone: [YOUR PHONE]

Please confirm removal within 30 days.

Regards,
[YOUR NAME]"""

    now = datetime.now().strftime("%Y-%m-%d %H:%M")

    html = f"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>OSINT Self-Report — {now}</title>
<style>
  :root {{
    --bg: #0f1117; --surface: #1a1d27; --border: #2a2d3e;
    --text: #e2e8f0; --muted: #8892b0; --accent: #64ffda;
    --critical: #ff6b6b; --high: #ffa94d; --medium: #74c0fc;
    --low: #a9e34b; --info: #8892b0;
  }}
  * {{ box-sizing: border-box; margin: 0; padding: 0; }}
  body {{ background: var(--bg); color: var(--text); font-family: 'Segoe UI', system-ui, sans-serif; font-size: 14px; }}
  header {{ background: var(--surface); border-bottom: 1px solid var(--border); padding: 16px 24px; display: flex; align-items: center; gap: 12px; }}
  header h1 {{ font-size: 18px; color: var(--accent); }}
  header span {{ color: var(--muted); font-size: 12px; }}
  .tabs {{ display: flex; background: var(--surface); border-bottom: 1px solid var(--border); padding: 0 24px; }}
  .tab {{ padding: 12px 20px; cursor: pointer; color: var(--muted); border-bottom: 2px solid transparent; transition: all .2s; }}
  .tab.active {{ color: var(--accent); border-bottom-color: var(--accent); }}
  .tab:hover {{ color: var(--text); }}
  .panel {{ display: none; padding: 24px; max-width: 1400px; margin: 0 auto; }}
  .panel.active {{ display: block; }}
  .cards {{ display: grid; grid-template-columns: repeat(auto-fit, minmax(160px, 1fr)); gap: 16px; margin-bottom: 24px; }}
  .card {{ background: var(--surface); border: 1px solid var(--border); border-radius: 8px; padding: 20px; text-align: center; }}
  .card .num {{ font-size: 36px; font-weight: 700; }}
  .card .label {{ color: var(--muted); font-size: 12px; margin-top: 4px; }}
  .card.critical .num {{ color: var(--critical); }}
  .card.high .num {{ color: var(--high); }}
  .card.medium .num {{ color: var(--medium); }}
  .card.low .num {{ color: var(--low); }}
  .card.info .num {{ color: var(--info); }}
  table {{ width: 100%; border-collapse: collapse; background: var(--surface); border-radius: 8px; overflow: hidden; }}
  th {{ background: #12141f; color: var(--muted); font-weight: 600; text-align: left; padding: 12px 16px; font-size: 12px; text-transform: uppercase; letter-spacing: .05em; }}
  td {{ padding: 12px 16px; border-top: 1px solid var(--border); vertical-align: top; word-break: break-word; }}
  tr:hover td {{ background: #1e2132; }}
  .badge {{ display: inline-block; padding: 2px 8px; border-radius: 4px; font-size: 11px; font-weight: 600; }}
  .badge-critical {{ background: rgba(255,107,107,.2); color: var(--critical); }}
  .badge-high {{ background: rgba(255,169,77,.2); color: var(--high); }}
  .badge-medium {{ background: rgba(116,192,252,.2); color: var(--medium); }}
  .badge-low {{ background: rgba(169,227,75,.2); color: var(--low); }}
  .badge-info {{ background: rgba(136,146,176,.15); color: var(--info); }}
  input, select {{ background: var(--surface); border: 1px solid var(--border); color: var(--text); padding: 8px 12px; border-radius: 6px; font-size: 13px; margin-right: 8px; }}
  input:focus, select:focus {{ outline: none; border-color: var(--accent); }}
  .filter-bar {{ margin-bottom: 16px; display: flex; flex-wrap: wrap; gap: 8px; }}
  a {{ color: var(--accent); text-decoration: none; }}
  a:hover {{ text-decoration: underline; }}
  pre {{ background: #12141f; border: 1px solid var(--border); border-radius: 6px; padding: 16px; overflow: auto; font-size: 12px; color: var(--muted); max-height: 500px; white-space: pre-wrap; word-break: break-all; }}
  .remediation-note {{ background: var(--surface); border: 1px solid var(--border); border-radius: 8px; padding: 16px; margin-bottom: 24px; }}
  .remediation-note h3 {{ color: var(--accent); margin-bottom: 8px; }}
  .identifiers {{ background: var(--surface); border: 1px solid var(--border); border-radius: 8px; padding: 16px; margin-bottom: 24px; }}
  .identifiers h3 {{ color: var(--accent); margin-bottom: 8px; }}
  .id-grid {{ display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 8px; }}
  .id-item {{ color: var(--muted); font-size: 12px; }}
  .id-item strong {{ color: var(--text); }}
</style>
</head>
<body>
<header>
  <h1>🔍 OSINT Self-Report</h1>
  <span>Generated {now} UTC — {len(findings)} total findings</span>
</header>

<div class="tabs">
  <div class="tab active" onclick="showTab('summary')">Summary</div>
  <div class="tab" onclick="showTab('findings')">Findings</div>
  <div class="tab" onclick="showTab('remediation')">Remediation</div>
  <div class="tab" onclick="showTab('raw')">Raw Data</div>
</div>

<div id="summary" class="panel active">
  <div class="cards">
    <div class="card critical"><div class="num">{severity_counts['Critical']}</div><div class="label">Critical</div></div>
    <div class="card high"><div class="num">{severity_counts['High']}</div><div class="label">High</div></div>
    <div class="card medium"><div class="num">{severity_counts['Medium']}</div><div class="label">Medium</div></div>
    <div class="card low"><div class="num">{severity_counts['Low']}</div><div class="label">Low</div></div>
    <div class="card info"><div class="num">{severity_counts['Info']}</div><div class="label">Info</div></div>
  </div>
  <div class="identifiers">
    <h3>Identifiers Scanned</h3>
    <div class="id-grid">
      <div class="id-item"><strong>Names:</strong> {', '.join(identifiers.get('names', [])) or 'none'}</div>
      <div class="id-item"><strong>Emails:</strong> {', '.join(identifiers.get('emails', [])) or 'none'}</div>
      <div class="id-item"><strong>Phones:</strong> {', '.join(set(identifiers.get('phones', []))) or 'none'}</div>
      <div class="id-item"><strong>Usernames:</strong> {', '.join(identifiers.get('usernames', [])) or 'none'}</div>
      <div class="id-item"><strong>Suburb:</strong> {identifiers.get('suburb', 'none')}</div>
    </div>
  </div>
  <table>
    <thead><tr><th>Module</th><th>Findings</th><th>Highest Severity</th></tr></thead>
    <tbody id="summary-tbody"></tbody>
  </table>
</div>

<div id="findings" class="panel">
  <div class="filter-bar">
    <input type="text" id="search" placeholder="Search..." oninput="filterFindings()">
    <select id="sev-filter" onchange="filterFindings()">
      <option value="">All severities</option>
      <option>Critical</option><option>High</option><option>Medium</option><option>Low</option><option>Info</option>
    </select>
    <select id="mod-filter" onchange="filterFindings()">
      <option value="">All modules</option>
    </select>
  </div>
  <table>
    <thead><tr><th>Severity</th><th>Module</th><th>Identifier</th><th>Title</th><th>Detail</th><th>Link</th></tr></thead>
    <tbody id="findings-tbody"></tbody>
  </table>
</div>

<div id="remediation" class="panel">
  <div class="remediation-note">
    <h3>Opt-out Email Template</h3>
    <pre>{optout_email_template}</pre>
  </div>
  <table>
    <thead><tr><th>Priority</th><th>Source</th><th>Opt-out</th><th>Action</th></tr></thead>
    <tbody>{remediation_rows if remediation_rows else '<tr><td colspan="4" style="color:var(--muted);text-align:center;padding:32px">No high-priority items found — great!</td></tr>'}</tbody>
  </table>
</div>

<div id="raw" class="panel">
  <pre id="raw-json"></pre>
</div>

<script>
const FINDINGS = {findings_json};

function badgeClass(sev) {{
  return 'badge badge-' + sev.toLowerCase();
}}

function showTab(id) {{
  document.querySelectorAll('.tab').forEach((t,i) => t.classList.remove('active'));
  document.querySelectorAll('.panel').forEach(p => p.classList.remove('active'));
  document.getElementById(id).classList.add('active');
  const tabs = ['summary','findings','remediation','raw'];
  document.querySelectorAll('.tab')[tabs.indexOf(id)].classList.add('active');
  if (id === 'raw') document.getElementById('raw-json').textContent = JSON.stringify(FINDINGS, null, 2);
}}

function populateSummary() {{
  const modules = {{}};
  const sevOrder = {{Critical:0,High:1,Medium:2,Low:3,Info:4}};
  FINDINGS.forEach(f => {{
    if (!modules[f.module]) modules[f.module] = {{count:0, sev:'Info'}};
    modules[f.module].count++;
    if (sevOrder[f.severity] < sevOrder[modules[f.module].sev]) modules[f.module].sev = f.severity;
  }});
  const tbody = document.getElementById('summary-tbody');
  Object.entries(modules).sort((a,b) => sevOrder[a[1].sev]-sevOrder[b[1].sev]).forEach(([mod,d]) => {{
    tbody.innerHTML += `<tr><td>${{mod}}</td><td>${{d.count}}</td><td><span class="${{badgeClass(d.sev)}}">${{d.sev}}</span></td></tr>`;
  }});
}}

function populateModuleFilter() {{
  const mods = [...new Set(FINDINGS.map(f => f.module))];
  const sel = document.getElementById('mod-filter');
  mods.forEach(m => sel.innerHTML += `<option>${{m}}</option>`);
}}

function filterFindings() {{
  const q = document.getElementById('search').value.toLowerCase();
  const sev = document.getElementById('sev-filter').value;
  const mod = document.getElementById('mod-filter').value;
  const filtered = FINDINGS.filter(f =>
    (!sev || f.severity === sev) &&
    (!mod || f.module === mod) &&
    (!q || JSON.stringify(f).toLowerCase().includes(q))
  );
  renderFindings(filtered);
}}

function renderFindings(data) {{
  const tbody = document.getElementById('findings-tbody');
  const sevOrder = {{Critical:0,High:1,Medium:2,Low:3,Info:4}};
  const sorted = [...data].sort((a,b) => sevOrder[a.severity]-sevOrder[b.severity]);
  tbody.innerHTML = sorted.map(f => `
    <tr>
      <td><span class="${{badgeClass(f.severity)}}">${{f.severity}}</span></td>
      <td>${{f.module}}</td>
      <td><code style="font-size:11px">${{f.identifier}}</code></td>
      <td>${{f.title}}</td>
      <td style="max-width:300px;font-size:12px;color:#8892b0">${{(f.detail||'').replace(/\\n/g,'<br>')}}</td>
      <td>${{f.url ? `<a href="${{f.url}}" target="_blank">Open</a>` : ''}}</td>
    </tr>`).join('');
  if (!sorted.length) tbody.innerHTML = '<tr><td colspan="6" style="color:var(--muted);text-align:center;padding:32px">No findings match filters.</td></tr>';
}}

populateSummary();
populateModuleFilter();
renderFindings(FINDINGS);
</script>
</body>
</html>"""

    return html


# ── Main runner ───────────────────────────────────────────────────────────────

async def run_all_modules(identifiers: dict, dry_run: bool) -> list[Finding]:
    import aiohttp

    if dry_run:
        print("\n[dry-run] Dependency and credential check complete. No requests made.")
        print(f"  DEHASHED_API_KEY:   {'set' if os.environ.get('DEHASHED_API_KEY') else 'not set'}")
        print(f"  INTELX_API_KEY:     {'set' if os.environ.get('INTELX_API_KEY') else 'not set'}")
        print(f"  GITHUB_TOKEN:       {'set' if os.environ.get('GITHUB_TOKEN') else 'not set'}")
        print(f"  NUMVERIFY_API_KEY:  {'set' if os.environ.get('NUMVERIFY_API_KEY') else 'not set'}")
        print(f"  LEAKCHECK_API_KEY:  {'set' if os.environ.get('LEAKCHECK_API_KEY') else 'not set'}")
        return []

    connector = aiohttp.TCPConnector(ssl=False, limit=10)
    timeout = aiohttp.ClientTimeout(total=30)

    all_findings: list[Finding] = []

    async with aiohttp.ClientSession(connector=connector, timeout=timeout) as session:
        print("\n[1/10] Google Dorks...")
        all_findings += await module_google_dorks(identifiers)

        print("[2/10] Data Broker Enumeration (Playwright)...")
        all_findings += await module_data_brokers(identifiers)

        print("[3/10] Username Enumeration (Sherlock)...")
        all_findings += await module_username_enum(identifiers)

        print("[4/10] Email Recon (Holehe + Epieos + DeHashed)...")
        all_findings += await module_email_recon(identifiers, session)

        print("[5/10] Phone Recon...")
        all_findings += await module_phone_recon(identifiers, session)

        print("[6/10] Breach / Paste Data...")
        all_findings += await module_breach_paste(identifiers, session)

        print("[7/10] GitHub / Code Leak...")
        all_findings += await module_github_search(identifiers, session)

        print("[8/10] Domain / WHOIS / crt.sh...")
        all_findings += await module_domain_crt(identifiers, session)

        print("[9/10] Dark Web Index (Ahmia)...")
        all_findings += await module_darkweb_ahmia(identifiers, session)

        print("[10/10] Social Presence...")
        all_findings += await module_social_presence(identifiers, session)

    return all_findings


def main():
    parser = argparse.ArgumentParser(
        description="OSINT Self-Recon — understand your own digital footprint."
    )
    parser.add_argument("--dry-run", action="store_true",
                        help="Validate dependencies and credentials only; make no external requests.")
    args = parser.parse_args()

    print("""
╔══════════════════════════════════════════════════════════╗
║          OSINT SELF-RECON TOOL  —  osint_self.py         ║
║  For personal use only. Scan your own footprint only.    ║
╚══════════════════════════════════════════════════════════╝""")

    if not check_dependencies(dry_run=args.dry_run):
        sys.exit(1)

    identifiers = prompt_identifiers()

    print("\n" + "─" * 60)
    print("Starting recon modules... (this may take several minutes)")
    print("─" * 60)

    findings = asyncio.run(run_all_modules(identifiers, dry_run=args.dry_run))

    if args.dry_run:
        sys.exit(0)

    # Save JSON
    output = {
        "generated": datetime.utcnow().isoformat(),
        "identifiers": {k: v for k, v in identifiers.items()},
        "findings": [f.to_dict() for f in findings],
    }
    with open("osint_results.json", "w") as fh:
        json.dump(output, fh, indent=2, default=str)
    print(f"\n[✓] Raw results saved → osint_results.json")

    # Generate HTML report
    html = generate_html_report(findings, identifiers)
    with open("osint_report.html", "w") as fh:
        fh.write(html)
    print(f"[✓] HTML report saved → osint_report.html")

    # Summary
    from collections import Counter
    sev_counts = Counter(f.severity for f in findings)
    print(f"\n{'─'*60}")
    print(f"  SCAN COMPLETE — {len(findings)} findings")
    print(f"  Critical: {sev_counts.get('Critical',0)}  High: {sev_counts.get('High',0)}  "
          f"Medium: {sev_counts.get('Medium',0)}  Low: {sev_counts.get('Low',0)}  Info: {sev_counts.get('Info',0)}")
    print(f"{'─'*60}")
    print("\nOpen osint_report.html in your browser to review results.\n")


if __name__ == "__main__":
    main()
