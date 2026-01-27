#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import pathlib
import re
import sys
from typing import Optional, Tuple


_APP_ROOT = pathlib.Path(__file__).resolve().parent.parent
_DEFAULT_LOGS_DIR = (_APP_ROOT / "var/logs").resolve()
LOGS_DIR = _DEFAULT_LOGS_DIR
if not LOGS_DIR.exists():
    LOGS_DIR = pathlib.Path("logs").resolve()

# Default tags to skip while finding the first character tag (name-only logic)
# These are not removals, only used to avoid picking a non-character tag name.
DEFAULT_SKIP_TAGS_FOR_NAME = {
    "system",
    "scenario",
    "example_dialogs",
    "persona",      # legacy
    "userpersona",  # canonical persona tag
}

# Default omit list: empty for a "normal" parse (no tag removals).
DEFAULT_OMIT_TAGS: set[str] = set()


def _replace_literal_newlines(text: str) -> str:
    return text.replace("\\n", "\n")


def _compile_tag_pair(name: str) -> Tuple[re.Pattern[str], re.Pattern[str]]:
    open_re = re.compile(rf"<\s*{re.escape(name)}\b[^>]*>", re.IGNORECASE)
    close_re = re.compile(rf"</\s*{re.escape(name)}\s*>", re.IGNORECASE)
    return open_re, close_re


def _remove_tag_blocks(text: str, name: str) -> str:
    """Remove every <name>...</name> block, handling nesting.

    If not properly closed, removes through end.
    """
    open_re, close_re = _compile_tag_pair(name)
    pos = 0
    while True:
        m_open = open_re.search(text, pos)
        if not m_open:
            break
        start = m_open.start()
        scan = m_open.end()
        depth = 1
        end_idx = len(text)
        while depth > 0:
            m_next_open = open_re.search(text, scan)
            m_next_close = close_re.search(text, scan)
            if not m_next_close:
                end_idx = len(text)
                break
            if m_next_open and m_next_open.start() < m_next_close.start():
                depth += 1
                scan = m_next_open.end()
                continue
            depth -= 1
            scan = m_next_close.end()
            end_idx = scan
        text = text[:start] + text[end_idx:]
        pos = start
    return text


def _find_first_non_skipped_tag(text: str, skip_for_name: set[str]) -> Optional[Tuple[str, int, int]]:
    """Find first opening tag <...> whose name is not in SKIP_TAGS.

    Allows spaces in tag name (e.g., "Miku and Nana"). Returns (name, open_start, open_end).
    """
    open_tag_re = re.compile(r"<\s*([^<>/]+?)\s*>", re.IGNORECASE)
    for m in open_tag_re.finditer(text):
        raw = m.group(1)
        name = raw.strip()
        if name.lower() in skip_for_name:
            continue
        return name, m.start(), m.end()
    return None


def _extract_tag_content(text: str, name: str, open_end: int) -> Tuple[int, int, str]:
    """Given <name> at open_end, return (content_start, block_end, inner_text)."""
    open_re, close_re = _compile_tag_pair(name)
    depth = 1
    scan = open_end
    block_end = len(text)
    inner_end = block_end
    while depth > 0:
        m_open = open_re.search(text, scan)
        m_close = close_re.search(text, scan)
        if not m_close:
            break
        if m_open and m_open.start() < m_close.start():
            depth += 1
            scan = m_open.end()
            continue
        depth -= 1
        if depth == 0:
            inner_end = m_close.start()
        scan = m_close.end()
        block_end = scan
    inner = text[open_end:inner_end]
    return open_end, block_end, inner


def _first_assistant_message(data: dict) -> Optional[str]:
    for msg in data.get("messages", []):
        if isinstance(msg, dict) and msg.get("role") == "assistant":
            content = msg.get("content", "")
            if content and content.strip():
                return _replace_literal_newlines(content)
    return None


def _sanitize_filename(name: str) -> str:
    safe = re.sub(r"[^0-9A-Za-z _\-()&]+", "_", name).strip()
    return safe or "character"


def _present_tag_names(text: str) -> set[str]:
    """Return a set of tag names present in the given text (opening tags only)."""
    names = set()
    # basic open-tag scan; keeps names as-lowered, ignores attributes
    for m in re.finditer(r"<\s*([^<>/]+?)\s*>", text, re.IGNORECASE):
        raw = m.group(1).strip()
        nm = raw.split()[0].lower()
        if nm:
            names.add(nm)
    return names


def _extract_all_tag_inners(text: str, name: str) -> list[str]:
    """Return a list of inner texts for all <name>..</name> blocks (handles nesting)."""
    results: list[str] = []
    open_re, close_re = _compile_tag_pair(name)
    pos = 0
    while True:
        m_open = open_re.search(text, pos)
        if not m_open:
            break
        open_end = m_open.end()
        depth = 1
        scan = open_end
        inner_end = len(text)
        while depth > 0:
            m_o = open_re.search(text, scan)
            m_c = close_re.search(text, scan)
            if not m_c:
                break
            if m_o and m_o.start() < m_c.start():
                depth += 1
                scan = m_o.end()
                continue
            depth -= 1
            if depth == 0:
                inner_end = m_c.start()
            scan = m_c.end()
        results.append(text[open_end:inner_end])
        pos = open_end
    return results


def process_json(
    path: pathlib.Path,
    *,
    omit_tags: set[str],
    skip_for_name: set[str],
    include_only: Optional[set[str]] = None,
    strip_tags: Optional[set[str]] = None,
    output_dir: Optional[pathlib.Path] = None,
    suffix: str = "",
) -> Optional[pathlib.Path]:
    raw = path.read_text(encoding="utf-8-sig")
    data = json.loads(raw)

    messages = data.get("messages", [])
    if not messages:
        print(f"[skip] {path.name}: no messages array")
        return None
    if not isinstance(messages[0], dict) or messages[0].get("role") != "system":
        print(f"[skip] {path.name}: first message is not 'system'")
        return None

    system_content = messages[0].get("content", "")
    system_content = _replace_literal_newlines(system_content)

    # Find first non-skipped tag in the original system content
    first = _find_first_non_skipped_tag(system_content, skip_for_name)
    has_char_block = first is not None
    if has_char_block:
        char_name, open_start, open_end = first  # type: ignore[misc]
        content_start_char, block_end_char, inner_raw = _extract_tag_content(system_content, char_name, open_end)
        # Strip "'s Persona" suffix from character name (common JanitorAI pattern)
        # Support various apostrophe characters: ' ' ʼ ʻ ʽ
        persona_suffix = re.match(r"^(.+?)[''ʼʻʽ]s\s+persona$", char_name, re.IGNORECASE)
        if persona_suffix:
            char_name = persona_suffix.group(1).strip()
    else:
        # Fallback: no character tag found. Proceed with untagged/scenario/first message handling
        char_name = "character"
        open_start = open_end = -1
        content_start_char = block_end_char = -1
        inner_raw = ""

    # Clean per rules (apply removals/whitelist, normalize newlines)
    inner_clean = inner_raw
    char_name_l = char_name.strip().lower()
    if include_only:
        # If the character tag itself is not selected, drop entire inner block
        if char_name_l not in include_only:
            inner_clean = ""
        else:
            # Isolation rule: character content should exclude other included tags.
            # 1) Remove any tags that are not included
            present = _present_tag_names(inner_clean)
            to_remove = {t for t in present if t.lower() not in include_only}
            for _tag in to_remove:
                inner_clean = _remove_tag_blocks(inner_clean, _tag)
            # 2) Also remove any other included tags (children) to avoid duplication
            included_children = {t for t in present if t.lower() in include_only and t.lower() != char_name_l}
            for _tag in included_children:
                inner_clean = _remove_tag_blocks(inner_clean, _tag)
    else:
        # Omit selected tags within the block
        for _tag in omit_tags:
            inner_clean = _remove_tag_blocks(inner_clean, _tag)
        # If the character tag itself is omitted, drop the whole inner block
        if char_name_l in omit_tags:
            inner_clean = ""
    # Unwrap specified tags (if any)
    for _tag in (strip_tags or ()):  # type: ignore[func-returns-value]
        inner_clean = _strip_tag_markers(inner_clean, _tag)
    inner_clean = _replace_literal_newlines(inner_clean).strip()

    # Extract <Scenario> content from the system message (outside of the character block)
    scenario_clean = ""
    sc_open_re, _ = _compile_tag_pair("scenario")
    m_sc = sc_open_re.search(system_content)
    if m_sc:
        sc_content_start, sc_block_end, sc_inner = _extract_tag_content(system_content, "scenario", m_sc.end())
        # Only add Scenario if it is outside the selected character block to avoid duplication
        if (not has_char_block) or (not (content_start_char <= m_sc.start() < block_end_char)):
            if include_only:
                # Keep Scenario only if explicitly selected
                if "scenario" not in include_only:
                    sc_inner = ""
                else:
                    present_sc = _present_tag_names(sc_inner)
                    # Remove not-included tags
                    to_remove_sc = {t for t in present_sc if t.lower() not in include_only}
                    for _tag in to_remove_sc:
                        sc_inner = _remove_tag_blocks(sc_inner, _tag)
                    # Isolation: also remove other included tags nested inside Scenario
                    included_sc = {t for t in present_sc if t.lower() in include_only and t.lower() != "scenario"}
                    for _tag in included_sc:
                        sc_inner = _remove_tag_blocks(sc_inner, _tag)
            else:
                # Omit inner tags first
                for _tag in omit_tags:
                    sc_inner = _remove_tag_blocks(sc_inner, _tag)
                # If Scenario itself is omitted, drop it
                if "scenario" in omit_tags:
                    sc_inner = ""
            for _tag in (strip_tags or ()):  # type: ignore[func-returns-value]
                sc_inner = _strip_tag_markers(sc_inner, _tag)
            scenario_clean = _replace_literal_newlines(sc_inner).strip()

    # Detect and extract any untagged content present in the first system message.
    # This is any text outside of recognized <tag>...</tag> blocks.
    untagged_clean = ""
    try:
        present_all = _present_tag_names(system_content)
        stripped = system_content
        for nm in list(present_all):
            stripped = _remove_tag_blocks(stripped, nm)
        # Remove any lingering tag markers like <foo> or </foo>
        stripped = re.sub(r"</?[^<>/]+?[^<>]*>", "", stripped)
        stripped = _replace_literal_newlines(stripped).strip()
        if include_only is not None:
            # Include only if explicitly selected
            if "untagged content" in include_only:
                untagged_clean = stripped
            else:
                untagged_clean = ""
        else:
            # Default mode: include unless explicitly omitted
            if "untagged content" in omit_tags:
                untagged_clean = ""
            else:
                untagged_clean = stripped
    except Exception:
        untagged_clean = ""

    # Include any other explicitly included top-level tags (e.g., userpersona)
    other_blocks: list[str] = []
    if include_only:
        for tag in include_only:
            if tag in {char_name_l, "scenario", "first_message"}:
                continue
            for inner in _extract_all_tag_inners(system_content, tag):
                inner2 = inner
                # Apply same filtering rules to inner2
                present = _present_tag_names(inner2)
                # Remove not-included tags first
                to_remove = {t for t in present if t.lower() not in include_only}
                for _tag in to_remove:
                    inner2 = _remove_tag_blocks(inner2, _tag)
                # Isolation: also remove other included tags so this tag's output is exclusive
                for _tag in {t for t in present if t.lower() in include_only and t.lower() != tag}:
                    inner2 = _remove_tag_blocks(inner2, _tag)
                for _tag in (strip_tags or ()):  # type: ignore[func-returns-value]
                    inner2 = _strip_tag_markers(inner2, _tag)
                inner2 = _replace_literal_newlines(inner2).strip()
                if inner2:
                    other_blocks.append(inner2)

    # First assistant message (omit user entirely)
    assistant_first = _first_assistant_message(data)
    include_first = True
    if include_only is not None:
        include_first = ("first_message" in include_only)
    else:
        include_first = ("first_message" not in omit_tags)

    # Compose output strictly based on include/exclude rules
    # In include-only mode, output ONLY explicitly included sections.
    out_lines: list[str] = []
    if include_only is not None:
        # Untagged content always first if selected
        if untagged_clean:
            out_lines.append(untagged_clean)
        # Character block only if explicitly included
        if char_name_l in include_only and inner_clean:
            if out_lines and out_lines[-1] != "":
                out_lines.append("")
            out_lines.append(inner_clean)
        # Other explicitly included top-level tags
        for blk in other_blocks:
            if blk:
                if out_lines and out_lines[-1] != "":
                    out_lines.append("")
                out_lines.append(blk)
        # Scenario only if explicitly included
        if "scenario" in include_only and scenario_clean:
            if out_lines and out_lines[-1] != "":
                out_lines.append("")
            out_lines.append(scenario_clean)
        # First assistant message only if explicitly included
        if assistant_first and include_first:
            if out_lines and out_lines[-1] != "":
                out_lines.append("")
            out_lines.extend(["First Message", "", assistant_first])
    else:
        # Default/omit mode: include everything except omitted pieces
        # Untagged content always first if present
        if untagged_clean:
            out_lines.append(untagged_clean)
        if inner_clean:
            if out_lines and out_lines[-1] != "":
                out_lines.append("")
            out_lines.append(inner_clean)
        for blk in other_blocks:
            if blk:
                if out_lines and out_lines[-1] != "":
                    out_lines.append("")
                out_lines.append(blk)
        if scenario_clean:
            if out_lines and out_lines[-1] != "":
                out_lines.append("")
            out_lines.append(scenario_clean)
        if assistant_first and include_first:
            out_lines.extend(["", "First Message", "", assistant_first])
    out_text = "\n".join(out_lines).rstrip() + "\n"

    # Determine output destination
    dest_dir = output_dir if output_dir else path.parent
    try:
        pathlib.Path(dest_dir).mkdir(parents=True, exist_ok=True)
    except Exception:
        pass

    safe_name = _sanitize_filename(char_name)
    suffix_norm = suffix.strip()
    if suffix_norm:
        filename = f"{safe_name}.{suffix_norm}.txt"
    else:
        filename = f"{safe_name}.txt"
    out_path = dest_dir / filename
    out_path.write_text(out_text, encoding="utf-8-sig")
    print(f"[OK] {path.name} → {out_path.name} ({len(out_text)} bytes)")
    return out_path


def _prompt_choice(prompt: str, choices: list[str], default: str) -> str:
    while True:
        raw = input(f"{prompt} {choices} [default: {default}]: ").strip().lower()
        if not raw:
            return default
        if raw in choices:
            return raw
        print(f"Please enter one of: {', '.join(choices)}")


def _prompt_tags(prompt: str) -> set[str]:
    raw = input(f"{prompt} (comma-separated, empty for none): ").strip()
    if not raw:
        return set()
    return {t.strip().lower() for t in raw.split(',') if t.strip()}


def _parse_args(argv: list[str]) -> tuple[list[pathlib.Path], set[str], set[str], Optional[set[str]], Optional[set[str]], Optional[pathlib.Path], str]:
    parser = argparse.ArgumentParser(description="Parse Janitor logs into character sheets.")
    parser.add_argument("paths", nargs="*", help="JSON files to process (defaults to logs/*.json)")
    parser.add_argument("--preset", choices=["default", "custom"], default=None,
                        help="default=no omissions; custom=prompt or supply tags")
    parser.add_argument("--omit-tags", dest="omit_tags", default="",
                        help="comma-separated tag names to remove (blacklist)")
    parser.add_argument("--include-tags", dest="include_tags", default="",
                        help="comma-separated tag names to include only (whitelist)")
    parser.add_argument("--strip-tags", dest="strip_tags", default="",
                        help="comma-separated tag names to unwrap (remove markers, keep content)")
    parser.add_argument("--include-mode", dest="include_mode", action="store_true",
                        help="force include-only mode even if no include-tags provided (includes nothing unless tags are explicitly listed)")
    parser.add_argument("--output-dir", dest="output_dir", default="",
                        help="directory to place parsed .txt outputs; defaults next to each JSON")
    parser.add_argument("--suffix", dest="suffix", default="",
                        help="optional suffix to append before .txt to version outputs (e.g., 2025-08-31_12-00-00__abcd1234)")

    ns = parser.parse_args(argv)

    # Targets
    if ns.paths:
        targets = [pathlib.Path(a) for a in ns.paths]
    else:
        if not LOGS_DIR.is_dir():
            print(f"[ERR] logs dir '{LOGS_DIR}' not found")
            targets = []
        else:
            targets = sorted(LOGS_DIR.glob("*.json"))
            print(f"[INFO] scanning {len(targets)} json files in '{LOGS_DIR}'")

    # Determine interactive vs non-interactive default behavior
    interactive = sys.stdin.isatty() and sys.stdout.isatty()
    preset = ns.preset or ("custom" if interactive else "default")

    # Build skip list (name detection) and tag filters
    skip_for_name = set(DEFAULT_SKIP_TAGS_FOR_NAME)
    omit_tags: set[str] = set(DEFAULT_OMIT_TAGS)
    include_only: Optional[set[str]] = None
    strip_tags: Optional[set[str]] = None

    if preset == "default":
        # No tag removals; ensure omit_tags is empty
        omit_tags = set()
    else:
        # custom - use CLI lists if provided, otherwise prompt if interactive
        cl_omit = {t.strip().lower() for t in (ns.omit_tags or "").split(',') if t.strip()}
        cl_include = {t.strip().lower() for t in (ns.include_tags or "").split(',') if t.strip()}
        cl_strip = {t.strip().lower() for t in (ns.strip_tags or "").split(',') if t.strip()}

        if not cl_omit and not cl_include and interactive:
            mode = _prompt_choice("Choose filter mode", ["omit", "include"], "omit")
            if mode == "omit":
                cl_omit = _prompt_tags("Enter tags to remove")
            else:
                cl_include = _prompt_tags("Enter tags to include only")

        if cl_include:
            include_only = set(cl_include)
        if cl_omit:
            omit_tags = set(cl_omit)
        if cl_strip:
            strip_tags = set(cl_strip)

        # Persona alias handling: only prompt if blacklist includes 'persona'
        # Always keep persona tags out of name detection
        skip_for_name.add("persona")
        skip_for_name.add("userpersona")

        # If explicitly forced into include-only mode and no include-tags were supplied,
        # use an empty include set (include nothing unless later specified by name).
        try:
            if getattr(ns, 'include_mode', False) and include_only is None and not omit_tags:
                include_only = set()
        except Exception:
            pass

    # Output options
    output_dir: Optional[pathlib.Path] = None
    if str(ns.output_dir or "").strip():
        output_dir = pathlib.Path(str(ns.output_dir).strip())
    suffix: str = str(ns.suffix or "").strip()

    return targets, omit_tags, skip_for_name, include_only, strip_tags, output_dir, suffix


def main(argv: list[str] | None = None) -> None:
    argv = argv or sys.argv[1:]
    targets, omit_tags, skip_for_name, include_only, strip_tags, output_dir, suffix = _parse_args(argv)
    if not targets:
        return

    done = 0
    had_error = False
    for t in targets:
        try:
            if process_json(
                t,
                omit_tags=omit_tags,
                skip_for_name=skip_for_name,
                include_only=include_only,
                strip_tags=strip_tags,
                output_dir=output_dir,
                suffix=suffix,
            ):
                done += 1
        except Exception as exc:
            print(f"[ERR] {t.name}: {exc}")
            had_error = True
    if len(argv or []) != 1 and done:
        print(f"[SUMMARY] finished {done}/{len(targets)} files")

    if had_error:
        sys.exit(1)
    sys.exit(0)


if __name__ == "__main__":
    main()
