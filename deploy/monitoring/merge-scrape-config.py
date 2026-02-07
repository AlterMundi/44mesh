#!/usr/bin/env python3
"""Merge 44mesh scrape jobs into VictoriaMetrics scrape config.

Reads the existing VM scrape config, removes any previous 44mesh jobs,
and appends the current ones from vmconfig-scrape-additions.yml.
"""
import os
import sys

try:
    import yaml
except ImportError:
    print("PyYAML not found, trying ruamel.yaml...", file=sys.stderr)
    try:
        from ruamel.yaml import YAML
        _ruamel = True
    except ImportError:
        print("ERROR: Neither PyYAML nor ruamel.yaml available.", file=sys.stderr)
        print("Install with: pip3 install pyyaml", file=sys.stderr)
        sys.exit(1)
else:
    _ruamel = False

VM_CONFIG = os.environ.get('VM_CONFIG')
if not VM_CONFIG:
    print("ERROR: VM_CONFIG environment variable is required.", file=sys.stderr)
    sys.exit(1)

ADDITIONS = os.environ.get('ADDITIONS')
if not ADDITIONS:
    print("ERROR: ADDITIONS environment variable is required.", file=sys.stderr)
    sys.exit(1)


def load_yaml(path):
    if _ruamel:
        y = YAML()
        with open(path) as f:
            return y.load(f)
    else:
        with open(path) as f:
            return yaml.safe_load(f)


def dump_yaml(data, path):
    if _ruamel:
        y = YAML()
        y.default_flow_style = False
        with open(path, 'w') as f:
            y.dump(data, f)
    else:
        with open(path, 'w') as f:
            yaml.dump(data, f, default_flow_style=False, sort_keys=False)


def main():
    try:
        config = load_yaml(VM_CONFIG) or {}
    except Exception as e:
        print(f"ERROR: Failed to parse {VM_CONFIG}: {e}", file=sys.stderr)
        sys.exit(1)
    try:
        additions = load_yaml(ADDITIONS) or {}
    except Exception as e:
        print(f"ERROR: Failed to parse {ADDITIONS}: {e}", file=sys.stderr)
        sys.exit(1)

    # Remove existing 44mesh jobs
    existing = [j for j in config.get('scrape_configs', [])
                if not j.get('job_name', '').startswith('44mesh')]

    # Append new 44mesh jobs
    new_jobs = additions.get('scrape_configs', [])
    config['scrape_configs'] = existing + new_jobs

    dump_yaml(config, VM_CONFIG)

    job_names = [j['job_name'] for j in new_jobs]
    print(f"Updated {VM_CONFIG}: added {', '.join(job_names)}")
    print(f"Total scrape jobs: {len(config['scrape_configs'])}")


if __name__ == '__main__':
    main()
