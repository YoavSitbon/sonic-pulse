"""Identify a song and fetch chord and lyric content from tab sources."""

import asyncio
import html
import json
import re
from typing import Any, Dict, Iterable, List, Optional
from urllib.parse import quote_plus, urljoin

import requests


TAB_SOURCES: Dict[str, Dict[str, Any]] = {
    "ultimate_guitar": {
        "name": "Ultimate Guitar",
        "languages": ["en"],
        "search_url": "https://www.ultimate-guitar.com/search.php?search_type=title&value={query}",
        "domains": ["ultimate-guitar.com"],
    },
    "tab4u": {
        "name": "Tab4U",
        "languages": ["he", "en"],
        "search_url": "https://www.tab4u.com/resultsSimple?tab=songs&q={query}",
        "domains": ["tab4u.com"],
    },
}

_CHORD_RE = re.compile(
    r"\b[A-G](?:#|b)?(?:maj|min|m|dim|aug|sus|add)?[0-9]*(?:/[A-G](?:#|b)?)?\b"
)
_HEBREW_RE = re.compile(r"[\u0590-\u05ff]")


class TabFinderService:
    """Find a song using ShazamIO and look up tabs from selected sources."""

    def find_tabs(
        self,
        *,
        title: Optional[str] = None,
        artist: Optional[str] = None,
        audio_path: Optional[str] = None,
        preferences: Optional[Dict[str, Iterable[str]]] = None,
    ) -> Dict[str, Any]:
        if audio_path:
            title, artist, metadata = self._recognize_audio(audio_path)
        else:
            title = (title or "").strip()
            artist = (artist or "").strip()
            metadata = {}

        if not title or not artist:
            raise ValueError("A song title and artist could not be determined")

        # Manual searches do not go through Shazam, so resolve a playable
        # preview independently. This also fills a missing Shazam preview.
        if not metadata.get("audio_url"):
            metadata.update(self._find_preview(title, artist))

        language = "he" if _HEBREW_RE.search(f"{title} {artist}") else "en"
        selected = self._selected_sources(language, preferences)
        tabs = [
            self._lookup_source(source_id, title, artist, language)
            for source_id in selected
        ]

        return {
            "success": True,
            "title": title,
            "artist": artist,
            "language": language,
            "audio_url": metadata.get("audio_url"),
            "artwork_url": metadata.get("artwork_url"),
            "tabs": [
                tab
                for tab in tabs
                if tab
                and (
                    tab.get("chord_content")
                )
            ],
        }

    def _selected_sources(
        self,
        language: str,
        preferences: Optional[Dict[str, Iterable[str]]],
    ) -> List[str]:
        requested = list((preferences or {}).get(language) or [])
        available = [
            source_id
            for source_id, source in TAB_SOURCES.items()
            if language in source["languages"]
        ]
        selected = [source_id for source_id in requested if source_id in available]
        return selected or available

    def _recognize_audio(self, audio_path: str):
        try:
            from shazamio import Shazam
        except ImportError as exc:
            raise RuntimeError(
                "Audio identification is unavailable: install shazamio"
            ) from exc

        async def recognize():
            shazam = Shazam()
            return await shazam.recognize(audio_path)

        response = asyncio.run(recognize())
        track = response.get("track") or {}
        title = (track.get("title") or "").strip()
        artist = (track.get("subtitle") or "").strip()
        actions = track.get("hub", {}).get("actions", [])
        audio_url = next(
            (action.get("uri") for action in actions if action.get("uri")),
            None,
        )
        return title, artist, {
            "audio_url": audio_url,
            "artwork_url": (track.get("images") or {}).get("coverart"),
        }

    @staticmethod
    def _find_preview(title: str, artist: str) -> Dict[str, Optional[str]]:
        """Find a short playable preview for title/artist searches."""
        try:
            response = requests.get(
                "https://itunes.apple.com/search",
                params={
                    "term": f"{title} {artist}",
                    "entity": "song",
                    "limit": 5,
                },
                timeout=10,
            )
            response.raise_for_status()
            results = response.json().get("results", [])
        except (requests.RequestException, ValueError):
            return {}

        if not results:
            return {}
        wanted_title = _normalize_match_text(title)
        wanted_artist = _normalize_match_text(artist)
        ranked = []
        for index, result in enumerate(results):
            result_title = _normalize_match_text(result.get("trackName", ""))
            result_artist = _normalize_match_text(result.get("artistName", ""))
            score = 0
            if result_title == wanted_title:
                score += 4
            elif wanted_title and wanted_title in result_title:
                score += 2
            if result_artist == wanted_artist:
                score += 4
            elif wanted_artist and wanted_artist in result_artist:
                score += 2
            ranked.append((score, -index, result))

        score, _, result = max(ranked)
        if score < 6:
            return {}
        return {
            "audio_url": result.get("previewUrl"),
            "artwork_url": result.get("artworkUrl100"),
        }

    def _lookup_source(
        self,
        source_id: str,
        title: str,
        artist: str,
        language: str,
    ) -> Optional[Dict[str, Any]]:
        source = TAB_SOURCES[source_id]
        query = quote_plus(f"{title} {artist}")
        search_url = source["search_url"].format(query=query)
        headers = {"User-Agent": "SonicPulse/1.0 (song tab lookup)"}

        try:
            response = requests.get(search_url, headers=headers, timeout=15)
            response.raise_for_status()
            page = response.text
        except requests.RequestException:
            return {
                "source_id": source_id,
                "source": source["name"],
                "language": language,
                "chord_content": "",
            }

        candidates = self._result_urls(page, source["domains"], search_url)
        if not candidates:
            return {
                "source_id": source_id,
                "source": source["name"],
                "language": language,
                "chord_content": "",
            }

        # Search pages often put a similarly named song first. Inspect a few
        # detail pages and choose the one whose metadata matches both fields.
        ranked = []
        for index, url in enumerate(candidates[:8]):
            try:
                detail = requests.get(url, headers=headers, timeout=15)
                detail.raise_for_status()
                candidate_page = detail.text
            except requests.RequestException:
                continue
            score = TabFinderService._match_score(
                candidate_page, title, artist
            )
            ranked.append((score, -index, candidate_page))

        if not ranked:
            content = page
        else:
            score, _, content = max(ranked)
            # Do not return lyrics from an unverified neighbouring result.
            # Hebrew pages commonly show the artist in Hebrew while catalogue
            # searches send the Latin transliteration (for example, "Omer
            # Adam" vs. "עומר אדם"). If the page title is an exact match,
            # accepting that result is safer than returning no tab at all.
            if score < 7 and not (
                language == "he"
                and self._has_exact_title(content, title)
                and score >= 4
            ):
                return None

        chords, chord_content, lyrics = self._extract_content(content)
        return {
            "source_id": source_id,
            "source": source["name"],
            "language": language,
            "chord_content": chord_content[:12000],
        }

    @staticmethod
    def _first_result_url(page: str, domains: List[str], fallback: str) -> str:
        urls = TabFinderService._result_urls(page, domains, fallback)
        return urls[0] if urls else ""

    @staticmethod
    def _result_urls(page: str, domains: List[str], fallback: str) -> List[str]:
        """Return unique likely song pages in the order shown by the site."""
        results = []
        # Ultimate Guitar exposes current search results in its embedded page
        # state rather than as anchor tags.
        embedded_urls = re.findall(
            r"[\"']tab_url[\"']\s*:\s*[\"']([^\"']+)[\"']",
            html.unescape(page),
            flags=re.I,
        )
        for link in embedded_urls:
            if any(domain in link for domain in domains) and "/tab/" in link:
                clean = link.split("#", 1)[0]
                if clean not in results:
                    results.append(clean)

        links = re.findall(r"href=[\"']([^\"']+)[\"']", page, flags=re.I)
        for link in links:
            link = html.unescape(link)
            if link.startswith("//"):
                link = "https:" + link
            if not re.match(r"https?://", link, re.I):
                link = urljoin(fallback, link)
            if not any(domain in link for domain in domains):
                continue
            if not re.search(r"/(?:tabs?/songs|tab)/", link, re.I):
                continue
            if re.search(r"(tab|chord|song|artist)", link, re.I):
                clean = link.split("#", 1)[0]
                if clean not in results:
                    results.append(clean)
        return results

    @staticmethod
    def _match_score(page: str, title: str, artist: str) -> int:
        """Score a detail page against the requested title and artist.

        The visible page title and OpenGraph title are weighted heavily. A
        match in the complete page is useful as a fallback because some tab
        sites put the artist in JSON-LD rather than visible HTML.
        """
        normalized_page = _normalize_match_text(page)
        normalized_title = _normalize_match_text(title)
        normalized_artist = _normalize_match_text(artist)
        score = 0
        title_matches = re.findall(r"<title[^>]*>(.*?)</title>", page, re.I | re.S)
        meta_matches = re.findall(
            r'<meta[^>]+(?:property|name)=["\'](?:og:title|twitter:title)["\'][^>]+content=["\']([^"\']+)',
            page,
            re.I,
        )
        page_title = " ".join(title_matches + meta_matches)
        normalized_heading = _normalize_match_text(page_title)
        for value, weight in ((normalized_title, 3), (normalized_artist, 3)):
            if value and value in normalized_heading:
                score += weight + 1
            elif value and value in normalized_page:
                score += 1
        return score

    @staticmethod
    def _has_exact_title(page: str, title: str) -> bool:
        """Check the page title metadata without requiring artist script match."""
        title_matches = re.findall(r"<title[^>]*>(.*?)</title>", page, re.I | re.S)
        meta_matches = re.findall(
            r'<meta[^>]+(?:property|name)=["\'](?:og:title|twitter:title)["\'][^>]+content=["\']([^"\']+)',
            page,
            re.I,
        )
        wanted = _normalize_match_text(title)
        headings = _normalize_match_text(" ".join(title_matches + meta_matches))
        return bool(wanted and wanted in headings)

    @staticmethod
    def _extract_content(page: str):
        """Extract displayable chord and lyric text from a fetched tab page.

        The source URL is used only internally to fetch the page and is never
        included in the API response. Preformatted blocks are preferred because
        most tab sites keep chord placement and lyrics there.
        """
        embedded = html.unescape(page)

        # Tab4U's table is the authoritative representation: it keeps the
        # chord-only rows, their original spacing, and the lyric rows in order.
        # Check it before generic embedded wiki markup, which drops that row
        # relationship and reintroduces indentation-only lines.
        tab4u_content = re.search(
            r'id=["\']songContentTPL["\'][^>]*>(.*?)(?:<table\s+id=["\']downInSongTable|</div>\s*<!--\s*songContentTPL)',
            page,
            flags=re.I | re.S,
        )
        if tab4u_content:
            parsed = TabFinderService._extract_tab4u_content(tab4u_content.group(1))
            if parsed[1]:
                return parsed

        embedded_match = re.search(
            r"[\"']wiki_tab[\"']\s*:\s*\{\s*[\"']content[\"']\s*:\s*[\"']((?:\\.|[^\"'\\])*)",
            embedded,
            flags=re.I,
        )
        if embedded_match:
            try:
                wiki_content = json.loads(f'"{embedded_match.group(1)}"')
                return TabFinderService._extract_markup_content(wiki_content)
            except (json.JSONDecodeError, TypeError):
                pass

        preformatted = re.findall(
            r"<pre[^>]*>(.*?)</pre>", page, flags=re.I | re.S
        )
        labelled = re.findall(
            r"class=[\"'][^\"']*chord[^\"']*[\"'][^>]*>(.*?)</",
            page,
            flags=re.I | re.S,
        )
        plain = re.sub(
            r"<script.*?</script>|<style.*?</style>|<nav.*?</nav>",
            " ",
            page,
            flags=re.I | re.S,
        )
        plain = re.sub(r"<[^>]+>", " ", plain)
        plain = html.unescape(plain)
        plain = " ".join(plain.split())
        pre_text = "\n\n".join(
            _clean_html_fragment(fragment) for fragment in preformatted
        ).strip()
        chord_text = pre_text or "\n".join(
            _clean_html_fragment(fragment) for fragment in labelled
        ).strip()
        tokens = labelled or _CHORD_RE.findall(plain)
        chords = []
        for token in tokens:
            token = _clean_html_fragment(token)
            match = _CHORD_RE.search(token)
            chord = match.group(0) if match else token
            if chord and chord not in chords:
                chords.append(chord)
        return chords[:80], chord_text, plain

    @staticmethod
    def _extract_markup_content(content: str):
        """Extract chords and lyrics from Ultimate Guitar's wiki markup."""
        chords = []
        for chord in re.findall(r"\[ch\](.*?)\[/ch\]", content, flags=re.I | re.S):
            chord = " ".join(chord.split())
            if chord and chord not in chords:
                chords.append(chord)

        formatted = re.sub(r"\[ch\](.*?)\[/ch\]", r"\1", content,
                           flags=re.I | re.S)
        formatted = re.sub(r"\[/?(?:tab|ch)\]", "", formatted,
                           flags=re.I)
        formatted = formatted.replace("\\r\\n", "\n").replace("\\n", "\n")
        formatted = html.unescape(formatted).strip()

        lyric_lines = []
        tab_blocks = re.findall(r"\[tab\](.*?)\[/tab\]", content,
                                flags=re.I | re.S)
        for block in tab_blocks:
            block = re.sub(r"\[ch\].*?\[/ch\]", "", block,
                           flags=re.I | re.S)
            block = block.replace("\\r\\n", "\n").replace("\\n", "\n")
            lyric_lines.append(html.unescape(block).rstrip())
        lyrics = "\n\n".join(lyric_lines).strip()
        return chords[:80], formatted, lyrics

    @staticmethod
    def _extract_tab4u_content(content: str):
        """Extract Tab4U's alternating chord/lyric table rows."""
        chords = []
        formatted_lines = []
        lyric_lines = []
        # Tab4U uses class="br" for transition blocks that are hidden by its
        # own stylesheet (.br { display: none; }). Remove those tables before
        # flattening rows so the API matches what the website displays.
        content = re.sub(
            r'<table[^>]*class=["\'][^"\']*\bbr\b[^"\']*["\'][^>]*>.*?</table>',
            "",
            content,
            flags=re.I | re.S,
        )
        rows = re.findall(r"<tr[^>]*>(.*?)</tr>", content, flags=re.I | re.S)
        pending_chord = ""
        pending_chords = []
        for row in rows:
            chord_match = re.search(
                r'<td[^>]*class=["\'][^"\']*chords[^"\']*["\'][^>]*>(.*?)</td>',
                row,
                flags=re.I | re.S,
            )
            song_match = re.search(
                r'<td[^>]*class=["\'][^"\']*song[^"\']*["\'][^>]*>(.*?)</td>',
                row,
                flags=re.I | re.S,
            )
            if chord_match:
                # Tab4U can place a chord-only row in a separate table. Keep
                # every pending row instead of replacing the previous one
                # when another chord row appears before the next lyric.
                if pending_chord:
                    pending_chords.append(pending_chord)
                pending_chord = _clean_html_fragment(
                    chord_match.group(1), preserve_whitespace=True
                )
                if not pending_chord.replace("\u00a0", " ").strip():
                    pending_chord = ""
                for chord in re.findall(
                    r"(?:N(?:\.?C\.?)?|[A-G](?:#|b)?(?:maj|min|m|dim|aug|sus|add)?[0-9]*(?:/[A-G](?:#|b)?)?)",
                    pending_chord,
                ):
                    if chord not in chords:
                        chords.append(chord)
            if not song_match:
                continue
            chord_lines = [*pending_chords]
            if pending_chord:
                chord_lines.append(pending_chord)
            pending_chords.clear()
            pending_chord = ""
            lyric_line = _clean_html_fragment(
                song_match.group(1), preserve_whitespace=True
            )
            # Lyric cells are right-aligned in the app; their source
            # indentation is not part of the chord coordinates. Keep chord
            # cell whitespace untouched, but remove indentation from lyrics.
            lyric_line = re.sub(r"^[\t \r\n\u00a0]+", "", lyric_line)
            lyric_line = re.sub(r"[\t \u00a0\r\n]+$", "", lyric_line)
            formatted_lines.extend(line for line in chord_lines if line)
            formatted_lines.append(lyric_line)
            if lyric_line:
                lyric_lines.append(lyric_line)

        # Preserve trailing chord-only rows too.
        if pending_chord:
            pending_chords.append(pending_chord)
        formatted_lines.extend(line for line in pending_chords if line)

        formatted_lines = [
            line
            if line.replace("\u00a0", " ").strip()
            else ""
            for line in formatted_lines
        ]

        # Some pages put the opening chord row in a separate table row before
        # the first lyric row. Keep it in the display content even if the
        # source did not give us a paired lyric row for that chord cell.
        chord_token = re.compile(
            r"^(?:N(?:\.?C\.?)?|[A-G](?:#|b)?(?:maj|min|m|dim|aug|sus|add)?[0-9]*(?:/[A-G](?:#|b)?)?)$",
            re.I,
        )
        has_chord_row = any(
            line.strip()
            and all(chord_token.fullmatch(token) for token in line.split())
            for line in formatted_lines
        )
        if chords and not has_chord_row:
            formatted_lines.insert(0, " ".join(chords))
        formatted_content = "\n".join(formatted_lines).strip("\n")
        # Remove indentation-only separator rows emitted by the HTML tables.
        formatted_content = re.sub(
            r"(?m)^[\t \u00a0]+$", "", formatted_content
        )
        return (
            chords[:80],
            formatted_content,
            "\n".join(lyric_lines).strip("\n"),
        )


def _clean_html_fragment(fragment: str, preserve_whitespace: bool = False) -> str:
    fragment = re.sub(r"<br\s*/?>", "\n", fragment, flags=re.I)
    # Tab4U represents a no-chord bar with an image. Preserve that semantic
    # marker instead of losing it when stripping HTML tags.
    fragment = re.sub(
        r'<img[^>]*src=["\'][^"\']*noChord\.svg[^"\']*["\'][^>]*>',
        "♫̸",
        fragment,
        flags=re.I,
    )
    fragment = re.sub(r"<[^>]+>", "", fragment)
    fragment = html.unescape(fragment).replace("\r", "")
    return fragment.strip("\n") if preserve_whitespace else fragment.strip()


def _normalize_match_text(value: str) -> str:
    """Normalize Latin/Hebrew search text without transliterating it."""
    value = html.unescape(value or "").lower()
    # Hebrew niqqud and cantillation marks should not affect matching.
    value = re.sub(r"[\u0591-\u05c7]", "", value)
    value = re.sub(r"[^\w\u0590-\u05ff]+", " ", value, flags=re.UNICODE)
    return " ".join(value.split())
