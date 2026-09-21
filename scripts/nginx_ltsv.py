#!/usr/bin/env python3
"""Set the chosen access log to LTSV, validating before a service reload."""

import argparse
import os
from pathlib import Path
import re
import shlex
import stat
import subprocess
import tempfile


FORMAT_NAME = "isucon_ltsv"
LOG_FORMAT = (
    "    log_format isucon_ltsv "
    "'time:$time_local\\thost:$remote_addr\\tmethod:$request_method"
    "\\turi:$request_uri\\tstatus:$status\\tsize:$body_bytes_sent"
    "\\treqtime:$request_time\\tapptime:$upstream_response_time';"
)


def statement_end(text, start):
    quote = None
    escaped = False
    comment = False
    for index in range(start, len(text)):
        char = text[index]
        if comment:
            comment = char != "\n"
        elif escaped:
            escaped = False
        elif char == "\\":
            escaped = True
        elif quote:
            if char == quote:
                quote = None
        elif char in ("'", '"'):
            quote = char
        elif char == "#":
            comment = True
        elif char == ";":
            return index + 1
    raise ValueError("Unterminated nginx directive")


def configure_format(text):
    pattern = re.compile(r"(?m)^[ \t]*log_format[ \t]+isucon_ltsv\b")
    for match in reversed(list(pattern.finditer(text))):
        end = statement_end(text, match.end())
        if text[end:end + 1] == "\n":
            end += 1
        text = text[:match.start()] + text[end:]
    blocks = list(re.finditer(r"(?m)^[ \t]*http\s*\{", text))
    if len(blocks) != 1:
        raise ValueError("NGINX_CONFIG must contain exactly one http block")
    end = blocks[0].end()
    rest = text[end:]
    if rest.startswith("\n"):
        rest = rest[1:]
    return text[:end] + "\n" + LOG_FORMAT + "\n" + rest


def nginx_quote(value):
    return '"' + value.replace("\\", "\\\\").replace('"', '\\"') + '"'


def configure_access(text, log_path):
    matches = list(re.finditer(r"(?m)^([ \t]*)access_log\s+", text))
    changed = 0
    for match in reversed(matches):
        end = statement_end(text, match.end())
        args = shlex.split(text[match.end():end - 1], comments=True)
        if not args or args[0] != log_path:
            continue
        options = args[2:] if len(args) > 1 else []
        suffix = "".join(" " + nginx_quote(value) for value in options)
        replacement = (
            f"{match[1]}access_log {nginx_quote(log_path)} {FORMAT_NAME}{suffix};"
        )
        text = text[:match.start()] + replacement + text[end:]
        changed += 1
    if not changed:
        raise ValueError("No matching access_log; check NGINX_ACCESS_CONFIG and NGINX_LOG")
    return text


def write_atomic(path, content):
    original = path.stat()
    descriptor, temporary = tempfile.mkstemp(prefix=".isucon-nginx-", dir=path.parent)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as file:
            file.write(content)
        os.chmod(temporary, stat.S_IMODE(original.st_mode))
        if os.geteuid() == 0:
            os.chown(temporary, original.st_uid, original.st_gid)
        os.replace(temporary, path)
    finally:
        Path(temporary).unlink(missing_ok=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", required=True)
    parser.add_argument("--access-config", required=True)
    parser.add_argument("--log", required=True)
    args = parser.parse_args()
    config = Path(args.config).resolve(strict=True)
    access = Path(args.access_config).resolve(strict=True)
    check = ["nginx", "-t", "-c", str(config)]
    subprocess.run(check, check=True)
    originals = {path: path.read_text(encoding="utf-8") for path in (config, access)}
    updated = dict(originals)
    updated[config] = configure_format(updated[config])
    updated[access] = configure_access(updated[access], args.log)
    written = []
    try:
        for path, content in updated.items():
            if content != originals[path]:
                write_atomic(path, content)
                written.append(path)
        subprocess.run(check, check=True)
    except BaseException:
        for path in reversed(written):
            write_atomic(path, originals[path])
        raise
    print(f"LTSV configured: {args.log}")


if __name__ == "__main__":
    main()
