"""
Notebook Reader Skill
=====================
A placeholder module for fetching text content from a given URL.
Designed for future NotebookLM integration.

Usage:
    reader = NotebookReader()
    content = reader.fetch_content("https://example.com")
"""

from __future__ import annotations

import logging
from dataclasses import dataclass, field
from typing import Optional

logger = logging.getLogger(__name__)


class NotebookReaderError(Exception):
    """Base exception for NotebookReader errors."""


class FetchError(NotebookReaderError):
    """Raised when content fetching fails."""


class ParseError(NotebookReaderError):
    """Raised when content parsing fails."""


@dataclass
class FetchResult:
    """Holds the result of a content fetch operation.

    Attributes:
        url: The source URL that was fetched.
        text: The extracted text content.
        title: The page title, if available.
        status_code: The HTTP status code of the response.
        content_type: The Content-Type header value.
    """

    url: str
    text: str
    title: Optional[str] = None
    status_code: int = 200
    content_type: Optional[str] = None
    metadata: dict = field(default_factory=dict)


class NotebookReader:
    """Fetches and extracts text content from a URL.

    This is a placeholder implementation intended to be extended
    for full NotebookLM integration. It provides the scaffolding
    for HTTP fetching and HTML-to-text extraction.

    Args:
        timeout: Request timeout in seconds (default: 30).
        user_agent: Custom User-Agent header string.
    """

    DEFAULT_USER_AGENT = (
        "NotebookReader/1.0 "
        "(+https://github.com/omar-fathalla/delegate_app)"
    )

    def __init__(
        self,
        timeout: int = 30,
        user_agent: Optional[str] = None,
    ) -> None:
        self.timeout = timeout
        self.user_agent = user_agent or self.DEFAULT_USER_AGENT

    def fetch_content(self, url: str) -> FetchResult:
        """Fetch and extract text content from the given URL.

        Args:
            url: The URL to fetch content from.

        Returns:
            A ``FetchResult`` containing the extracted text and metadata.

        Raises:
            FetchError: If the HTTP request fails.
            ParseError: If HTML parsing fails.
        """
        try:
            import requests  # noqa: F811 – deferred import
        except ImportError as exc:
            raise NotebookReaderError(
                "The 'requests' package is required. "
                "Install it with: pip install requests"
            ) from exc

        logger.info("Fetching content from: %s", url)

        try:
            response = requests.get(
                url,
                timeout=self.timeout,
                headers={"User-Agent": self.user_agent},
            )
            response.raise_for_status()
        except requests.RequestException as exc:
            raise FetchError(
                f"Failed to fetch URL '{url}': {exc}"
            ) from exc

        raw_html = response.text
        content_type = response.headers.get("Content-Type", "")

        text, title = self._parse_html(raw_html)

        return FetchResult(
            url=url,
            text=text,
            title=title,
            status_code=response.status_code,
            content_type=content_type,
            metadata={
                "content_length": len(raw_html),
                "extracted_length": len(text),
            },
        )

    def _parse_html(self, html: str) -> tuple[str, Optional[str]]:
        """Parse HTML and extract plain text and title.

        Args:
            html: Raw HTML string.

        Returns:
            A tuple of (extracted_text, page_title).

        Raises:
            ParseError: If parsing fails.
        """
        try:
            from bs4 import BeautifulSoup  # noqa: F811 – deferred import
        except ImportError as exc:
            raise NotebookReaderError(
                "The 'beautifulsoup4' package is required. "
                "Install it with: pip install beautifulsoup4"
            ) from exc

        try:
            soup = BeautifulSoup(html, "html.parser")

            # Remove script and style elements
            for element in soup(["script", "style", "nav", "footer"]):
                element.decompose()

            title_tag = soup.find("title")
            title = title_tag.get_text(strip=True) if title_tag else None

            text = soup.get_text(separator="\n", strip=True)

            return text, title

        except Exception as exc:
            raise ParseError(
                f"Failed to parse HTML content: {exc}"
            ) from exc

    def __repr__(self) -> str:
        return (
            f"NotebookReader(timeout={self.timeout}, "
            f"user_agent='{self.user_agent}')"
        )


# ---------------------------------------------------------------------------
# Quick self-test when run directly
# ---------------------------------------------------------------------------
if __name__ == "__main__":
    import sys

    logging.basicConfig(level=logging.INFO)

    test_url = sys.argv[1] if len(sys.argv) > 1 else "https://example.com"
    reader = NotebookReader()

    try:
        result = reader.fetch_content(test_url)
        print(f"Title : {result.title}")
        print(f"Status: {result.status_code}")
        print(f"Length: {result.metadata.get('extracted_length', 0)} chars")
        print("-" * 60)
        print(result.text[:500])
    except NotebookReaderError as err:
        print(f"Error: {err}", file=sys.stderr)
        sys.exit(1)
