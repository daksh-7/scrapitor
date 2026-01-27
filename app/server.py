from __future__ import annotations

import datetime as dt
import json
import logging
import os
import pathlib
import string
import re
import subprocess
import sys
import time
from typing import Any, Dict, Optional

import requests
from flask import Flask, Response, jsonify, request, stream_with_context, send_from_directory
from flask_cors import CORS

# Import tag utilities from parser (handles both module and direct execution)
try:
    from app.parser.parser import _compile_tag_pair, _remove_tag_blocks
except ImportError:
    from parser.parser import _compile_tag_pair, _remove_tag_blocks


# ── .env loader ──────────────────────────────────────────────
def _load_dotenv() -> None:
    """Load .env file from repo root if it exists. Env vars take precedence."""
    # Find repo root (parent of app/)
    app_dir = pathlib.Path(__file__).parent.resolve()
    repo_root = app_dir.parent
    env_file = repo_root / '.env'

    if not env_file.exists():
        return

    try:
        with open(env_file, 'r', encoding='utf-8') as f:
            for line in f:
                line = line.strip()
                # Skip comments and empty lines
                if not line or line.startswith('#'):
                    continue
                # Parse KEY=VALUE
                if '=' in line:
                    key, _, value = line.partition('=')
                    key = key.strip()
                    value = value.strip()
                    # Remove surrounding quotes
                    if (value.startswith('"') and value.endswith('"')) or \
                       (value.startswith("'") and value.endswith("'")):
                        value = value[1:-1]
                    # Only set if not already defined
                    if key and key not in os.environ:
                        os.environ[key] = value
    except Exception:
        pass

# Load .env before building config
_load_dotenv()

# ── config ───────────────────────────────────────────────────
def _load_config() -> Dict[str, Any]:
    def env(k, default, cast=str):
        v = os.getenv(k)
        if v is None:
            return default
        try:
            return cast(v)
        except Exception:
            return default

    raw_allowed = os.getenv("ALLOWED_ORIGINS", "*")
    allowed_list = [origin.strip() for origin in raw_allowed.split(",") if origin.strip()]
    if not allowed_list:
        allowed_list = ["*"]

    return {
        "server": {
            "port": env("PROXY_PORT", 5000, int),
            "allowed_origins": allowed_list,
            "connect_timeout": env("CONNECT_TIMEOUT", 5.0, float),
            "read_timeout": env("READ_TIMEOUT", 300.0, float),
        },
        "openrouter": {
            "url": os.getenv("OPENROUTER_URL", "https://openrouter.ai/api/v1/chat/completions"),
            "api_key": os.getenv("OPENROUTER_API_KEY", ""),
            "allow_server_api_key": str(os.getenv("ALLOW_SERVER_API_KEY", "false")).lower() in ("1", "true", "yes", "on"),
            "defaults": {"temperature": 1.0, "top_p": 1.0, "top_k": 0, "max_tokens": 1024},
        },
        "logging": {
            "directory": os.getenv("LOG_DIR", "var/logs"),
            "max_files": env("MAX_LOG_FILES", 1000, int),
            "level": os.getenv("LOG_LEVEL", "INFO"),
        },
        "parser": {"mode": "default", "include_tags": [], "exclude_tags": []},
        "security": {"max_messages": 50, "max_model_length": 100, "validate_requests": True},
    }

CONFIG = _load_config()

_raw_level = CONFIG["logging"].get("level", logging.INFO)
if isinstance(_raw_level, str):
    name = _raw_level.strip()
    level_value = getattr(logging, name.upper(), None)
    if isinstance(level_value, int):
        log_level = level_value
    else:
        try:
            log_level = int(name)
        except (TypeError, ValueError):
            log_level = logging.INFO
elif isinstance(_raw_level, int):
    log_level = _raw_level
else:
    log_level = logging.INFO

logging.basicConfig(
    level=log_level,
    format="%(asctime)s - %(levelname)s - %(message)s",
)
log = logging.getLogger("proxy")

OPENROUTER_URL = CONFIG["openrouter"]["url"]
LISTEN_PORT = CONFIG["server"]["port"]
TIMEOUT = (CONFIG["server"]["connect_timeout"], CONFIG["server"]["read_timeout"])
BASE_DIR = pathlib.Path(__file__).parent
LOG_DIR = (BASE_DIR / CONFIG["logging"].get("directory", "var/logs")).resolve(); LOG_DIR.mkdir(parents=True, exist_ok=True)
PARSED_ROOT = (LOG_DIR / "parsed").resolve(); PARSED_ROOT.mkdir(parents=True, exist_ok=True)
MAX_LOG_FILES = CONFIG["logging"]["max_files"]
GEN_CFG = CONFIG["openrouter"]["defaults"].copy()
STARTED_MONO = time.monotonic()
STARTED_EPOCH = time.time()

# Parser settings (mutable at runtime, persisted under var/state)
_PARSER_SETTINGS_PATH = (BASE_DIR / "var/state/parser_settings.json").resolve()
_PARSER_SETTINGS_PATH.parent.mkdir(parents=True, exist_ok=True)

def _load_parser_settings() -> Dict[str, Any]:
    base = {
        "mode": str(CONFIG["parser"].get("mode", "default")),
        # include_tags are ephemeral; do not preload from config
        "include_tags": [],
        "exclude_tags": list(CONFIG["parser"].get("exclude_tags", [])),
    }
    try:
        if _PARSER_SETTINGS_PATH.exists():
            disk = json.loads(_PARSER_SETTINGS_PATH.read_text(encoding="utf-8"))
            if isinstance(disk, dict):
                if "preset" in disk or "omit_tags" in disk or "include_tags" in disk:
                    preset = str(disk.get("preset", "default")).lower()
                    if preset == "default":
                        disk["mode"] = "default"
                        # Clear include tags; they are not persisted
                        disk["include_tags"] = []
                        disk.setdefault("exclude_tags", [])
                    else:
                        disk["mode"] = "custom"
                        # Clear include tags; they are not persisted
                        disk["include_tags"] = []
                        disk.setdefault("exclude_tags", disk.get("omit_tags", []))
                for k in ("mode","include_tags","exclude_tags"):
                    if k in disk:
                        base[k] = disk[k]
    except Exception as e:
        log.warning(f"Failed to read parser_settings.json: {e}")
    return base

def _save_parser_settings(settings: Dict[str, Any]) -> None:
    try:
        _PARSER_SETTINGS_PATH.write_text(json.dumps(settings, ensure_ascii=False, indent=2), encoding="utf-8")
    except Exception as e:
        log.warning(f"Failed to write parser_settings.json: {e}")

PARSER_SETTINGS = _load_parser_settings()

# Shared parameter bounds
BOUNDS = {
    "temperature": (0, 2, float),
    "top_p": (0, 1, float),
    "top_k": (0, 200, int),
    "max_tokens": (1, 4096, int),
}

# ── session ──────────────────────────────────────────────────
sess = requests.Session()
adapter = requests.adapters.HTTPAdapter(pool_connections=10, pool_maxsize=10, max_retries=3)
sess.mount("http://", adapter); sess.mount("https://", adapter)
sess.headers.update({
    "Content-Type": "application/json",
    "Referer": "https://janitorai.com/",
    "X-Title": "JanitorAI-Local-Proxy",
})
_do_post   = lambda **kw: sess.post(OPENROUTER_URL, timeout=TIMEOUT, **kw)
_do_stream = lambda **kw: sess.post(OPENROUTER_URL, stream=True, timeout=TIMEOUT, **kw)

# ── utils ────────────────────────────────────────────────────
def _ts() -> str:
    now = dt.datetime.now(dt.timezone.utc)
    return now.strftime("%Y-%m-%d_%H-%M-%S_%f")[:-3]

def _safe_name(seed: str) -> str:
    allowed = set(string.ascii_letters + string.digits + "-_ .")
    s = "".join(c for c in (seed or "") if c in allowed).strip()[:100]
    return s or "log"

def _prune_logs() -> None:
    files = sorted(LOG_DIR.glob("*.json"), key=lambda p: p.stat().st_mtime, reverse=True)
    for old in files[MAX_LOG_FILES:]:
        try:
            old.unlink()
        except Exception as e:
            log.warning(f"Failed to delete old log {old.name}: {e}")

def _build_sillytavern_json(name: str, description: str, scenario: str, first_mes: str) -> dict:
    """Build a SillyTavern-compatible character card JSON (chara_card_v3 spec)."""
    # Normalize newlines to \r\n for SillyTavern compatibility
    def norm(s: str) -> str:
        return s.replace('\r\n', '\n').replace('\n', '\r\n').strip()
    
    name = name.strip()
    description = norm(description)
    scenario = norm(scenario)
    first_mes = norm(first_mes)
    
    now = dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%f")[:-3] + "Z"
    
    return {
        "name": name,
        "description": description,
        "personality": "",
        "scenario": scenario,
        "first_mes": first_mes,
        "mes_example": "",
        "creatorcomment": "",
        "avatar": "none",
        "talkativeness": "0.5",
        "fav": False,
        "tags": [],
        "spec": "chara_card_v3",
        "spec_version": "3.0",
        "data": {
            "name": name,
            "description": description,
            "personality": "",
            "scenario": scenario,
            "first_mes": first_mes,
            "mes_example": "",
            "creator_notes": "",
            "system_prompt": "",
            "post_history_instructions": "",
            "tags": [],
            "creator": "",
            "character_version": "",
            "alternate_greetings": [],
            "extensions": {
                "talkativeness": "0.5",
                "fav": False,
                "world": "",
                "depth_prompt": {
                    "prompt": "",
                    "depth": 4,
                    "role": "system"
                }
            },
            "group_only_greetings": []
        },
        "create_date": now
    }


def _save_log(payload: dict) -> None:
    try:
        path = LOG_DIR / f"{_safe_name(_ts())}.json"
        path.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
        _prune_logs()

        parser = pathlib.Path(__file__).parent / "parser" / "parser.py"
        if parser.exists():
            try:
                # Build parser args based on current settings
                args = _build_parser_args(path)
                res = subprocess.run(args, capture_output=True, text=True)
                if res.stdout.strip(): log.debug(f"Parser stdout: {res.stdout.strip()}")
                if res.stderr.strip(): log.warning(f"Parser stderr: {res.stderr.strip()}")
            except Exception as e:
                log.warning(f"Parser.py failed: {e}")
    except Exception as e:
        log.error(f"Failed to save log: {e}")

def _next_version_suffix_for(json_path: pathlib.Path) -> str:
    """Return next human-friendly version label like 'v3' for parsed TXT outputs.

    Versioning is scoped to the parsed directory for this JSON's stem.
    """
    base_dir = _parsed_output_dir_for(json_path)
    try:
        base_dir.mkdir(parents=True, exist_ok=True)
    except Exception:
        pass
    max_v = 0
    try:
        for p in base_dir.glob("*.v*.txt"):
            name = p.name
            try:
                after = name.rsplit('.v', 1)[1]
                num = after.split('.txt', 1)[0]
                v = int(''.join(ch for ch in num if ch.isdigit()))
                if v > max_v:
                    max_v = v
            except Exception:
                continue
    except Exception:
        pass
    return f"v{max_v + 1}"


def _parsed_output_dir_for(json_path: pathlib.Path) -> pathlib.Path:
    # Place versions under var/logs/parsed/<json_stem>/
    return (PARSED_ROOT / json_path.stem).resolve()


def _resolve_log_path(name: str) -> Optional[pathlib.Path]:
    raw = str(name or '').strip()
    if not raw:
        return None
    candidate = raw if raw.endswith('.json') else f"{raw}.json"
    path = (LOG_DIR / candidate)
    try:
        resolved = path.resolve(strict=False)
        resolved.relative_to(LOG_DIR)
    except Exception:
        return None
    if resolved.exists() and resolved.is_file():
        return resolved
    return None


def _build_parser_args(json_path: pathlib.Path, override: Optional[Dict] = None) -> list[str]:
    args = [sys.executable, str(pathlib.Path(__file__).parent / "parser" / "parser.py")]
    settings = override or PARSER_SETTINGS
    mode = str(settings.get("mode", "default")).lower()
    include_tags = [str(x).strip() for x in settings.get("include_tags", []) if str(x).strip()]
    exclude_tags = [str(x).strip() for x in settings.get("exclude_tags", []) if str(x).strip()]
    if mode == "custom":
        # Always run in custom preset; choose include or omit flags accordingly
        args += ["--preset", "custom"]
        if include_tags:
            args += ["--include-tags", ",".join(include_tags)]
        elif exclude_tags:
            args += ["--omit-tags", ",".join(exclude_tags)]
        else:
            # Force include-only mode with an empty include set (include nothing)
            args += ["--include-mode"]
    else:
        args += ["--preset", "default"]
    # Output routing and versioning
    out_dir = _parsed_output_dir_for(json_path)
    suffix = _next_version_suffix_for(json_path)
    args += ["--output-dir", str(out_dir), "--suffix", suffix]

    # no persona mapping; persona tag is always 'UserPersona'
    args.append(str(json_path))
    return args

def _validate_payload(pl: dict) -> dict:
    if not CONFIG["security"]["validate_requests"]:
        return pl
    if not isinstance(pl, dict) or not isinstance(pl.get("messages"), list):
        raise ValueError("`messages` must be an array")

    messages = pl["messages"][: CONFIG["security"]["max_messages"]]

    def clamp(value, lo, hi, cast, default):
        try:
            return max(lo, min(hi, cast(value)))
        except Exception:
            return max(lo, min(hi, cast(default)))

    out = {
        "model": str(pl.get("model", ""))[: CONFIG["security"]["max_model_length"]],
        "messages": messages,
        "stream": bool(pl.get("stream", False)),
    }
    for key, (lo, hi, cast) in BOUNDS.items():
        out[key] = clamp(pl.get(key, GEN_CFG[key]), lo, hi, cast, GEN_CFG[key])
    return out

def _auth_headers(client_auth: str) -> dict:
    """Build upstream Authorization header with safe defaults.

    - Prefer the client-provided Authorization header.
    - Only fall back to a server-side API key if explicitly enabled via
      ALLOW_SERVER_API_KEY=true (or config openrouter.allow_server_api_key).
    - Never forward client tokens in non-standard headers.
    """
    headers: Dict[str, str] = {}
    client_auth = (client_auth or "").strip()
    if client_auth:
        headers["Authorization"] = client_auth
        return headers

    if CONFIG["openrouter"].get("allow_server_api_key") and CONFIG["openrouter"].get("api_key"):
        headers["Authorization"] = f"Bearer {CONFIG['openrouter']['api_key']}"
    return headers

def _stream_back(payload: dict, headers: dict):
    try:
        hdrs = dict(headers)
        hdrs.setdefault("Accept", "text/event-stream")
        with _do_stream(json=payload, headers=hdrs) as r:
            r.raise_for_status()
            for chunk in r.iter_lines():
                # OpenRouter streams Server-Sent Events already ("data: {...}\n\n")
                if chunk and chunk != b": OPENROUTER PROCESSING":
                    yield chunk + b"\n\n"
    except requests.exceptions.RequestException as e:
        err = {"error": {"message": str(e), "type": "stream_error"}}
        yield f"data: {json.dumps(err)}\n\n".encode()

# ── app ──────────────────────────────────────────────────────
def create_app() -> Flask:
    app = Flask(__name__, static_folder='static', static_url_path='/static')
    # Honor X-Forwarded-* headers from cloudflared so url_for and request.url_root are correct
    try:
        from werkzeug.middleware.proxy_fix import ProxyFix
        app.wsgi_app = ProxyFix(app.wsgi_app, x_for=1, x_proto=1, x_host=1, x_prefix=1)
    except Exception:
        pass

    # Allow cross-origin access (including Authorization header) so the
    # JanitorAI site or other tools can call the proxy via the Cloudflare URL.
    # Use configured origins (default: "*") to permit restriction if desired.
    try:
        allowed = CONFIG["server"].get("allowed_origins", ["*"])
        if isinstance(allowed, str):
            allowed = [allowed]
    except Exception:
        allowed = ["*"]
    CORS(
        app,
        resources={r"/*": {"origins": allowed}},
        allow_headers=["Content-Type", "Authorization"],
        expose_headers=["Content-Type"],
        supports_credentials=False,
    )

    @app.route("/openrouter-cc", methods=["GET", "POST", "OPTIONS"])
    def openrouter_cc():
        if request.method == "OPTIONS":
            return "", 204
        if request.method == "GET":
            return jsonify({
                "status": "alive",
                "message": "Proxy alive - POST your /chat/completions here",
                "version": "2.0",
                "config": {"max_messages": CONFIG["security"]["max_messages"]},
            })
        return _handle_completion()

    # Optional alias to match OpenAI route shape if you want:
    @app.route("/chat/completions", methods=["POST"])
    def chat_completions():
        return _handle_completion()

    def _handle_completion():
        if not request.is_json:
            return jsonify({"error": "Only application/json accepted"}), 415

        client_auth = request.headers.get("Authorization", "")

        # No mandatory server-side API key; client should supply Authorization header.

        payload_in = request.get_json(silent=True)
        if not isinstance(payload_in, dict):
            return jsonify({"error": "Request body must be a JSON object"}), 400

        # fire-and-forget log write (synchronous but quick, no thread)
        _save_log(dict(payload_in))

        try:
            payload = _validate_payload(payload_in)
        except ValueError as e:
            return jsonify({"error": str(e)}), 400

        headers = _auth_headers(client_auth)
        # Fail fast if no Authorization available (prevents accidental credit usage patterns)
        if "Authorization" not in headers:
            return jsonify({"error": "Missing Authorization header. Provide your OpenRouter API key as an Authorization bearer token."}), 401

        if payload.get("stream"):
            gen = stream_with_context(_stream_back(payload, headers))
            return Response(gen, mimetype="text/event-stream")

        try:
            r = _do_post(json=payload, headers=headers)
            r.raise_for_status()
            return r.json(), r.status_code
        except requests.exceptions.HTTPError as e:
            try:
                detail = e.response.json().get("error", {}).get("message", str(e))
            except Exception:
                detail = f"OpenRouter error: {getattr(e.response,'status_code', 'unknown')}"
            log.error(f"OpenRouter HTTP error: {detail}")
            return jsonify({"error": detail}), 502
        except Exception as e:
            log.exception("Unexpected error")
            return jsonify({"error": "Internal server error"}), 500

    @app.route("/models")
    def models():
        return {
            "object": "list",
            "data": [{"id": "openrouter-proxy", "object": "model", "created": 0, "owned_by": "janitorai-local-proxy"}],
        }

    @app.route("/param", methods=["GET", "POST"])
    def param():
        if request.method == "POST":
            data = request.get_json(silent=True) or {}
            for k, (lo, hi, cast) in BOUNDS.items():
                if k in data:
                    try:
                        GEN_CFG[k] = max(lo, min(hi, cast(data[k])))
                    except Exception:
                        pass
        return jsonify(GEN_CFG)

    @app.route("/logs")
    def list_logs():
        files = sorted(LOG_DIR.glob("*.json"), key=lambda p: p.stat().st_mtime, reverse=True)
        items = []
        since_start = 0
        for p in files:
            try:
                st = p.stat()
                mtime = st.st_mtime
                if mtime >= STARTED_EPOCH:
                    since_start += 1
                items.append({"name": p.name, "mtime": mtime, "size": st.st_size})
            except Exception:
                continue
        # Total parsed txts (all-time)
        parsed_total = 0
        try:
            for _ in PARSED_ROOT.rglob("*.txt"):
                parsed_total += 1
        except Exception:
            parsed_total = 0
        names = [it["name"] for it in items[:50]]
        return jsonify({
            "logs": names,
            "items": items[:200],
            "total": since_start,
            "total_all": len(files),
            "parsed_total": parsed_total,
            "recent": names
        })

    @app.route("/logs/<name>")
    def get_log(name: str):
        safe = _safe_name(name)
        if not safe.endswith(".json"):
            safe += ".json"
        p = LOG_DIR / safe
        if p.exists() and p.is_file():
            try:
                return p.read_text(encoding="utf-8"), 200, {"Content-Type": "application/json"}
            except Exception as e:
                return jsonify({"error": f"Failed to read log: {e}"}), 500
        return jsonify({"error": f"{safe} not found"}), 404

    @app.route("/logs/<name>/parsed", methods=["GET"])
    def list_parsed_versions(name: str):
        safe = _safe_name(name)
        if safe.endswith(".json"):
            stem = pathlib.Path(safe).stem
        else:
            stem = pathlib.Path(safe + ".json").stem
        base_dir = _parsed_output_dir_for(LOG_DIR / f"{stem}.json")
        try:
            if not base_dir.exists() or not base_dir.is_dir():
                return jsonify({"versions": [], "latest": ""})
            files = sorted(base_dir.glob("*.txt"), key=lambda p: p.stat().st_mtime, reverse=True)
            out = []
            latest_id = ""
            highest_v = -1
            for i, p in enumerate(files):
                try:
                    st = p.stat()
                    ver = None
                    nm = p.name
                    if ".v" in nm:
                        try:
                            after = nm.rsplit('.v', 1)[1]
                            num = after.split('.txt', 1)[0]
                            ver = int(''.join(ch for ch in num if ch.isdigit()))
                            if ver is not None and ver > highest_v:
                                highest_v = ver
                                latest_id = p.name
                        except Exception:
                            pass
                    item = {
                        "id": p.name,
                        "file": p.name,
                        "size": st.st_size,
                        "mtime": st.st_mtime,
                        "version": ver,
                    }
                    out.append(item)
                except Exception:
                    continue
            if not latest_id and out:
                latest_id = out[0]["file"]
            return jsonify({"versions": out, "latest": latest_id, "dir": base_dir.name})
        except Exception as e:
            return jsonify({"versions": [], "error": str(e)}), 500

    @app.route("/logs/<name>/parsed/<path:fname>", methods=["GET"])
    def get_parsed_content(name: str, fname: str):
        safe = _safe_name(name)
        if safe.endswith(".json"):
            stem = pathlib.Path(safe).stem
        else:
            stem = pathlib.Path(safe + ".json").stem
        base_dir = _parsed_output_dir_for(LOG_DIR / f"{stem}.json")
        target = (base_dir / fname).resolve()
        try:
            # Ensure target is inside base_dir
            if base_dir not in target.parents:
                return jsonify({"error": "Invalid path"}), 400
            if target.exists() and target.is_file() and target.suffix.lower() == ".txt":
                return target.read_text(encoding="utf-8-sig"), 200, {"Content-Type": "text/plain; charset=utf-8"}
            return jsonify({"error": f"{fname} not found"}), 404
        except Exception as e:
            return jsonify({"error": str(e)}), 500

    @app.route("/logs/<name>/parsed/delete", methods=["POST"])
    def delete_parsed_files(name: str):
        """Delete one or more parsed .txt files for a given log."""
        data = request.get_json(silent=True) or {}
        files = data.get("files") or []
        if isinstance(files, str):
            files = [files]
        files = [str(f).strip() for f in files if str(f).strip()]
        if not files:
            return jsonify({"deleted": 0, "results": [], "error": "no files provided"}), 400
        safe = _safe_name(name)
        stem = pathlib.Path(safe if safe.endswith('.json') else safe + '.json').stem
        base_dir = _parsed_output_dir_for(LOG_DIR / f"{stem}.json")
        results = []
        deleted = 0
        for fn in files:
            try:
                p = (base_dir / pathlib.Path(fn).name).resolve()
                if base_dir not in p.parents or p.suffix.lower() != '.txt':
                    results.append({"file": fn, "ok": False, "error": "invalid path"})
                    continue
                if p.exists() and p.is_file():
                    p.unlink()
                    deleted += 1
                    results.append({"file": fn, "ok": True})
                else:
                    results.append({"file": fn, "ok": False, "error": "not found"})
            except Exception as e:
                results.append({"file": fn, "ok": False, "error": str(e)})
        return jsonify({"deleted": deleted, "results": results})

    @app.route("/logs/delete", methods=["POST"])
    def delete_logs():
        """Delete one or more activity log JSON files and their parsed directories."""
        data = request.get_json(silent=True) or {}
        files = data.get("files") or []
        if isinstance(files, str):
            files = [files]
        files = [str(f).strip() for f in files if str(f).strip()]
        if not files:
            return jsonify({"deleted": 0, "results": [], "error": "no files provided"}), 400
        results = []
        deleted = 0
        for raw in files:
            try:
                safe = _safe_name(raw)
                if not safe.endswith('.json'):
                    safe += '.json'
                p = (LOG_DIR / safe).resolve()
                if LOG_DIR not in p.parents:
                    results.append({"file": raw, "ok": False, "error": "invalid path"})
                    continue
                # Delete JSON file
                if p.exists() and p.is_file():
                    p.unlink()
                else:
                    results.append({"file": raw, "ok": False, "error": "not found"})
                    continue
                # Delete parsed directory if present
                try:
                    parsed_dir = _parsed_output_dir_for(p)
                    if parsed_dir.exists() and parsed_dir.is_dir():
                        for sub in parsed_dir.glob("*"):
                            try:
                                sub.unlink()
                            except Exception:
                                pass
                        try:
                            parsed_dir.rmdir()
                        except Exception:
                            pass
                except Exception:
                    pass
                deleted += 1
                results.append({"file": raw, "ok": True})
            except Exception as e:
                results.append({"file": raw, "ok": False, "error": str(e)})
        return jsonify({"deleted": deleted, "results": results})

    @app.route("/logs/<name>/rename", methods=["POST"])
    def rename_log(name: str):
        data = request.get_json(silent=True) or {}
        new_name_raw = str(data.get("new_name", "")).strip()
        if not new_name_raw:
            return jsonify({"error": "new_name is required"}), 400
        old_safe = _safe_name(name)
        if not old_safe.endswith('.json'):
            old_safe += '.json'
        old_path = LOG_DIR / old_safe
        if not old_path.exists():
            return jsonify({"error": f"{old_safe} not found"}), 404
        new_safe = _safe_name(new_name_raw)
        if not new_safe.endswith('.json'):
            new_safe += '.json'
        new_path = LOG_DIR / new_safe
        if new_path.exists():
            return jsonify({"error": "A file with that name already exists"}), 409
        try:
            old_path.rename(new_path)
            # Move parsed dir if present
            old_dir = _parsed_output_dir_for(old_path)
            new_dir = _parsed_output_dir_for(new_path)
            if old_dir.exists() and old_dir.is_dir():
                try:
                    old_dir.rename(new_dir)
                except Exception:
                    pass
            return jsonify({"old": old_safe, "new": new_safe})
        except Exception as e:
            return jsonify({"error": str(e)}), 500

    @app.route("/logs/<name>/parsed/rename", methods=["POST"])
    def rename_parsed_txt(name: str):
        data = request.get_json(silent=True) or {}
        old_file = str(data.get("old", "")).strip()
        new_file_raw = str(data.get("new", "")).strip()
        if not old_file or not new_file_raw:
            return jsonify({"error": "old and new are required"}), 400
        safe = _safe_name(name)
        if not safe.endswith('.json'):
            safe += '.json'
        base_dir = _parsed_output_dir_for(LOG_DIR / safe)
        old_p = (base_dir / pathlib.Path(old_file).name).resolve()
        new_safe = _safe_name(new_file_raw)
        if not new_safe.endswith('.txt'):
            new_safe += '.txt'
        new_p = (base_dir / new_safe).resolve()
        try:
            if base_dir not in old_p.parents or base_dir not in new_p.parents:
                return jsonify({"error": "Invalid path"}), 400
            if not old_p.exists() or not old_p.is_file():
                return jsonify({"error": "Source file not found"}), 404
            if new_p.exists():
                return jsonify({"error": "Destination already exists"}), 409
            new_p.write_text(old_p.read_text(encoding='utf-8-sig'), encoding='utf-8-sig')
            try:
                old_p.unlink()
            except Exception:
                pass
            return jsonify({"old": old_p.name, "new": new_p.name})
        except Exception as e:
            return jsonify({"error": str(e)}), 500

    @app.route("/parser-settings", methods=["GET", "POST"])
    def parser_settings():
        global PARSER_SETTINGS
        if request.method == "POST":
            data = request.get_json(silent=True) or {}
            mode = str(data.get("mode", PARSER_SETTINGS.get("mode", "default"))).lower()
            if mode not in ("default", "custom"):
                mode = "default"

            def _norm_list(v):
                if isinstance(v, str):
                    return [s.strip() for s in v.split(',') if s.strip()]
                if isinstance(v, list):
                    return [str(s).strip() for s in v if str(s).strip()]
                return []

            # Persist exclusions only; include tags are ephemeral
            exclude_tags = _norm_list(data.get("exclude_tags", PARSER_SETTINGS.get("exclude_tags", [])))
            PARSER_SETTINGS = {
                "mode": mode,
                "include_tags": [],
                "exclude_tags": exclude_tags,
            }
            _save_parser_settings(PARSER_SETTINGS)
        # Never return persisted include_tags
        resp = dict(PARSER_SETTINGS)
        resp["include_tags"] = []
        return jsonify(resp)

    @app.route("/parser-rewrite", methods=["POST"])
    def parser_rewrite():
        data = request.get_json(silent=True) or {}
        mode = str(data.get("mode", "all")).lower()
        # Optional per-request parser overrides
        parser_mode = str(data.get("parser_mode", PARSER_SETTINGS.get("mode", "default"))).lower()

        def _norm_list(v):
            if isinstance(v, str):
                return [s.strip() for s in v.split(',') if s.strip()]
            if isinstance(v, list):
                return [str(s).strip() for s in v if str(s).strip()]
            return []

        include_override = _norm_list(data.get("include_tags", []))
        exclude_override = _norm_list(data.get("exclude_tags", []))
        # Respect explicit empty lists from the client; only fall back if key absent
        provided_exclude = ("exclude_tags" in data)
        override_settings = {
            "mode": parser_mode,
            "include_tags": include_override,
            "exclude_tags": (exclude_override if provided_exclude else PARSER_SETTINGS.get("exclude_tags", [])),
        }

        files_in = data.get("files", [])
        targets: list[pathlib.Path] = []
        if isinstance(files_in, list) and files_in:
            seen: set[pathlib.Path] = set()
            for raw in files_in:
                resolved = _resolve_log_path(raw)
                if resolved and resolved not in seen:
                    targets.append(resolved)
                    seen.add(resolved)
        else:
            files = sorted(LOG_DIR.glob("*.json"), key=lambda p: p.stat().st_mtime, reverse=True)
            targets = files if mode != "latest" else (files[:1] if files else [])

        results = []
        for t in targets:
            try:
                args = _build_parser_args(t, override=override_settings)
                res = subprocess.run(args, capture_output=True, text=True)
                ok = res.returncode == 0
                results.append({
                    "file": t.name,
                    "ok": ok,
                    "stdout": res.stdout.strip(),
                    "stderr": res.stderr.strip(),
                })
            except Exception as e:
                results.append({"file": t.name, "ok": False, "error": str(e)})
        return jsonify({"rewritten": len(results), "results": results})

    @app.route("/tunnel", methods=["GET"])
    def tunnel():
        try:
            p = BASE_DIR / "var/state/tunnel_url.txt"
            if p.exists():
                url = p.read_text(encoding="utf-8").strip()
                return jsonify({"url": url})
        except Exception:
            pass
        return jsonify({"url": ""})

    @app.route("/parser-tags", methods=["GET"])
    def parser_tags():
        """Return tag names detected from selected log file(s).

        Query params:
        - file: may repeat multiple times
        - files: comma-separated list
        If none provided, falls back to latest.
        """
        names_in = set()
        for n in request.args.getlist("file"):
            n = (n or "").strip()
            if n:
                names_in.add(n)
        csv = (request.args.get("files", "") or "").strip()
        if csv:
            for n in csv.split(','):
                n = n.strip()
                if n:
                    names_in.add(n)

        files = sorted(LOG_DIR.glob("*.json"), key=lambda p: p.stat().st_mtime, reverse=True)
        targets = []
        if names_in:
            for raw in names_in:
                safe = _safe_name(raw)
                if not safe.endswith('.json'):
                    safe += '.json'
                cand = LOG_DIR / safe
                if cand.exists():
                    targets.append(cand)
        else:
            if files:
                targets = [files[0]]

        if not targets:
            return jsonify({"tags": [], "files": [], "by_file": {}, "by_tag": {}})

        names = set()
        used = []
        file_to_tags: Dict[str, list[str]] = {}
        for target in targets:
            try:
                data = json.loads(target.read_text(encoding='utf-8'))
                msgs = data.get('messages', [])
                content = ""
                if msgs and isinstance(msgs[0], dict) and msgs[0].get('role') == "system":
                    content = str(msgs[0].get('content', ""))
                tagset = set()
                for m in re.finditer(r"<\s*([^<>/]+?)\s*>", content, re.IGNORECASE):
                    nm = m.group(1).strip()
                    if not nm:
                        continue
                    # Normalize to the bare tag name (before any attributes)
                    nm0 = nm.split()[0]
                    if nm0:
                        names.add(nm0)
                        tagset.add(nm0)
                # Detect untagged content: remove all detected tag blocks and any stray tag markers,
                # then see if any non-whitespace remains.
                if content:
                    stripped = content
                    for nm in list(tagset):
                        try:
                            stripped = _remove_tag_blocks(stripped, nm)
                        except Exception:
                            # Best-effort; continue if any edge case
                            pass
                    # Remove any remaining tag markers like <foo> or </foo>
                    stripped = re.sub(r"</?[^<>/]+?[^<>]*>", "", stripped)
                    # If anything other than whitespace remains, treat as 'Untagged Content'
                    if stripped and stripped.strip():
                        tagset.add('Untagged Content')
                        names.add('Untagged Content')
                used.append(target.name)
                file_to_tags[target.name] = sorted({t.strip() for t in tagset if t.strip()}, key=lambda x: x.lower())
            except Exception:
                continue

        tag_to_files: Dict[str, list[str]] = {}
        for fname, tags in file_to_tags.items():
            for t in tags:
                tag_to_files.setdefault(t, []).append(fname)
        for t, lst in tag_to_files.items():
            tag_to_files[t] = sorted(lst)
        return jsonify({
            "tags": sorted(names, key=lambda x: x.lower()),
            "files": used,
            "by_file": file_to_tags,
            "by_tag": tag_to_files,
        })

    @app.route("/export-sillytavern", methods=["POST"])
    def export_sillytavern():
        """Export parsed TXT files to SillyTavern-compatible JSON."""
        data = request.get_json(silent=True) or {}

        def _norm_list(v):
            if isinstance(v, str):
                return [s.strip() for s in v.split(',') if s.strip()]
            if isinstance(v, list):
                return [str(s).strip() for s in v if str(s).strip()]
            return []

        exports = []

        # Export from existing parsed TXT files
        log_name = str(data.get("log_name", "")).strip()
        txt_files = _norm_list(data.get("txt_files", []))

        if not log_name or not txt_files:
            return jsonify({"exports": [], "count": 0, "error": "log_name and txt_files required"}), 400

        # Resolve log directory
        safe = _safe_name(log_name)
        if safe.endswith(".json"):
            stem = pathlib.Path(safe).stem
        else:
            stem = safe
        base_dir = _parsed_output_dir_for(LOG_DIR / f"{stem}.json")

        for txt_file in txt_files:
            try:
                txt_path = (base_dir / pathlib.Path(txt_file).name).resolve()
                if not txt_path.exists() or txt_path.suffix.lower() != '.txt':
                    continue

                content = txt_path.read_text(encoding='utf-8-sig')

                # Name is filename minus .txt
                name = txt_path.stem
                # Handle "[Name]'s Persona" pattern - extract just the name
                # Support various apostrophe characters: ' ' ʼ ʻ ʽ
                persona_match = re.match(r"^(.+?)[''ʼʻʽ]s\s+persona$", name, re.IGNORECASE)
                if persona_match:
                    name = persona_match.group(1).strip()

                # Split by "First Message" marker
                first_mes_marker = "First Message"
                description = ""
                first_mes = ""
                scenario = ""

                if first_mes_marker in content:
                    parts = content.split(first_mes_marker, 1)
                    description = parts[0].strip()
                    first_mes = parts[1].strip() if len(parts) > 1 else ""
                else:
                    description = content.strip()

                # Build the JSON
                st_json = _build_sillytavern_json(name, description, scenario, first_mes)
                safe_filename = re.sub(r"[^0-9A-Za-z _\-()&]+", "_", name).strip() or "character"

                exports.append({
                    "name": name,
                    "filename": f"{safe_filename}.json",
                    "source_txt": txt_file,
                    "json": st_json,
                })
            except Exception as e:
                log.warning(f"Failed to export {txt_file}: {e}")
                continue

        return jsonify({"exports": exports, "count": len(exports)})

    @app.route("/health")
    def health():
        return jsonify({
            "status": "healthy",
            "uptime_seconds": round(time.monotonic() - STARTED_MONO, 3),
            "version": "2.0",
            "config": {"port": LISTEN_PORT},
        })

    return app

app = create_app()

# SPA build location
_SPA_DIST = BASE_DIR / "static" / "dist"
if not (_SPA_DIST / "index.html").exists():
    log.warning(f"SPA dist not found at {_SPA_DIST}")

@app.route("/")
def ui():
    return send_from_directory(_SPA_DIST, "index.html"), 200, {
        "Cache-Control": "no-store, no-cache, must-revalidate, max-age=0"
    }

@app.route("/assets/<path:filename>")
def spa_assets(filename: str):
    resp = send_from_directory(_SPA_DIST / "assets", filename)
    resp.headers["Cache-Control"] = "public, max-age=31536000, immutable"
    return resp


@app.errorhandler(500)
def internal_error(e):
    log.exception("Internal server error")
    return jsonify({
        "error": "Internal server error",
        "message": "An unexpected error occurred"
    }), 500


# ── run ───────────────────────────────────────────────────
if __name__ == "__main__":
    os.chdir(pathlib.Path(__file__).parent.resolve())
    
    # Show configuration summary
    log.info(f"Starting JanitorAI Proxy on port {LISTEN_PORT}")
    log.info(f"API key configured: {bool(CONFIG['openrouter']['api_key'])}")
    if CONFIG["openrouter"].get("api_key") and not CONFIG["openrouter"].get("allow_server_api_key"):
        log.info("Server API key present but disabled by default (ALLOW_SERVER_API_KEY=false). Requests must supply Authorization header.")
    log.info(f"Allowed origins: {CONFIG['server']['allowed_origins']}")
    
    app.run(host="0.0.0.0", port=LISTEN_PORT, threaded=True, debug=False)
