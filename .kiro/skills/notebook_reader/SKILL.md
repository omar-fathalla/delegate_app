---
name: notebook_reader
description: Fetch text content from a given URL for NotebookLM integration.
---

# Notebook Reader Skill

## Overview
This skill provides a utility to fetch and extract text content from a given URL. It is designed to be used as a building block for **NotebookLM** integration, allowing the agent to ingest web-based content into a notebook source.

## Usage

### When to Use
- When the user asks to fetch or read content from a URL for use in NotebookLM.
- When preparing web content as a source for a NotebookLM notebook.

### How to Use
1. Import the `NotebookReader` class from `notebook_reader.py`.
2. Create an instance of `NotebookReader`.
3. Call `fetch_content(url)` with the target URL.
4. The method returns the extracted text content as a string.

### Example
```python
from notebook_reader import NotebookReader

reader = NotebookReader()
content = reader.fetch_content("https://example.com/article")
print(content)
```

## Script Location
- **Script:** `scripts/notebook_reader.py`

## Dependencies
- Python 3.8+
- `requests` (HTTP library)
- `beautifulsoup4` (HTML parsing)

## Limitations
- This is a **placeholder** implementation intended to be extended.
- Does not handle JavaScript-rendered pages (use a headless browser for those).
- Basic error handling is included; production usage should add retries and rate limiting.
