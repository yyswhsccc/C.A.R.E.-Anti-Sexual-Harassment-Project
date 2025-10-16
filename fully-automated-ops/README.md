# Fully-Automated Ops (sanitized)

My instance-side automation: Bash/Python scripts, cron jobs, and systemd units.

- **scripts/**: collected from /usr/local/bin, /opt, and ~/bin (sanitized).
- **cron/**: cron.d, daily/hourly jobs, and the root crontab (sanitized).
- **systemd/**: service/timer units that call local scripts.
- **MANIFEST.csv**: original absolute path → repo path mapping.

> Secrets are scrubbed where patterns were detected and replaced with `REDACTED`.
> Purpose is to showcase structure and approach, not to run in production as-is.
