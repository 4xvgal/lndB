# lndB Project Documentation

**Author:** jm lim  
**Last Updated:** $(date +%Y-%m-%d)

## 1. Project Summary

- **Project Name:** lndB
- **Goal:** Build a Zero-Knowledge Backup system that enforces the 3-2-1 rule using bash automation, cron schedules, and PGP asymmetric encryption across local, mounted, and remote/cloud targets with multi-stage alerting.
- **Key Technologies:** bash, cron, gpg, tar, gzip, scp/ssh, optional cloud CLIs (S3/B2/R2/etc.), Docker compatibility (Alpine-first mindset).
- **Primary Dataset:** LND node data such as `channel.backup`, `chan-backup-archives/`, and `wallet.db` (customizable via `BASE_CHAIN_DIR`, `RELATIVE_FILE_TARGETS`, `RELATIVE_DIR_TARGETS`, and `EXTRA_TARGETS`).

## 2. Requirements Overview

### A. Backup Targets
- Capture entire LND channel data plus configurable directories.

### B. Encryption (PGP Zero-Knowledge)
- Use asymmetric PGP encryption (import existing public keys or generate new ones).
- Identify keys via user input or `.env`/config.
- Produce a single encrypted archive (`.tar.gz.gpg`).

### C. Runtime Environment
- Executable by dedicated or general-purpose users.
- Designed for cron automation (daily default, customizable cadence).

### D. Storage & Retention (3-2-1)
1. Local disk storage (primary).
2. Mounted external disk storage (must be mounted; treat unmounted state as fatal).
3. Remote server replication via `scp` over SSH.
4. (Phase 2) Cloud uploads via provider CLIs.
5. Configurable retention (30/60/90 days defaults).

### E. Phase 1 Network Transfer
- `scp` over SSH with key-based auth to remote backup targets.

### F. Phase 2 Cloud Backup
- Selectable providers (S3/B2/R2/etc.).
- Prefer provider-specific CLIs over `rclone`.
- Uploads only the PGP-encrypted artifact (no streaming uploads; file-first flow).

### G. Phase 3 Alerting
1. Telegram Bot (mandatory).
2. Email fallback (SMTP/sendmail/postfix).
- Failure triggers: encryption/storage/mount/remote/cloud errors.
- Missing mount == immediate global failure.
- Alerts must reflect error category and log context.

### H. Configuration & Logging
- Central config file `lndb.conf`.
- Logs at `/var/log/lndb.log` with future logrotate option.
- Optional automatic package installation (`AUTO_INSTALL_MISSING_BINS`, `PACKAGE_MANAGER_OVERRIDE`) for missing binaries.
- Backup targets stay tidy via `BASE_CHAIN_DIR` plus `RELATIVE_FILE_TARGETS`, `RELATIVE_DIR_TARGETS`, and optional `EXTRA_TARGETS`.
- Manual trigger helper `trigger_backup.sh` provides `TRIGGER_MODE` control to run locally, request a systemd unit (`SYSTEMD_UNIT_NAME`), or signal a long-lived daemon (`DAEMON_PID_FILE`, `DAEMON_SIGNAL`).
- `test_encrypt.sh` exercises compression + encryption only so you can validate artifacts before enabling remote transfers (`TEST_WORK_DIR`, `TEST_LOG_FILE` tunable).
- Crypto inputs allow multiple key provisioning paths via `GPG_KEY_SOURCE` (`existing`, `file`, `keyserver`, `url`, or `auto`) plus helpers such as `GPG_PUBLIC_KEY_FILE`, `GPG_KEY_URL`, `GPG_KEYSERVER`, `GPG_KEY_ID`, and `GPG_RECIPIENT_FINGERPRINT`.
- Supported OS: Ubuntu, Debian, Alpine (+ Docker containers).
- Verify or auto-install required binaries.

## 3. System Architecture
```
backup.sh
 ├─ Tar → gzip → PGP encrypt
 ├─ Local store
 ├─ Mounted disk store (+mount check)
 ├─ scp to remote server
 ├─ (Phase 2) Cloud upload via modules/cloud.sh
 ├─ Cleanup (retention)
 └─ Alerting (Phase 3 via modules/notify.sh)
```

## 4. Proposed File Structure
```
/opt/lndb/
  ├─ backup.sh
  ├─ trigger_backup.sh
  ├─ test_encrypt.sh
  ├─ lndb.conf
  ├─ modules/
  │    ├─ cloud.sh
  │    └─ notify.sh
  └─ logs/
      └─ lndb.log
```

## 5. Phase Planning

### Manual Trigger Flow
- `trigger_backup.sh` reads `lndb.conf` and issues immediate backup commands.
- `TRIGGER_MODE=direct` (default) runs `backup.sh` immediately.
- `TRIGGER_MODE=systemd` issues `systemctl start $SYSTEMD_UNIT_NAME`.
- `TRIGGER_MODE=signal` sends `DAEMON_SIGNAL` (default `USR1`) to the PID in `DAEMON_PID_FILE` so a long-lived daemon can react.

### Encryption Test Flow
- `test_encrypt.sh` sources the main script logic and runs only the compression + encryption phases.
- Outputs land under `TEST_WORK_DIR` (default: `./tmp/test-encrypt`) and respect all crypto settings (`GPG_*`).
- Use this helper before enabling network transfers to confirm keys and archives are generated correctly.

### Phase 1 — Local + Mount + Remote Backup
- **Status:** In progress.
- **Deliverables:** Working `backup.sh` and `lndb.conf` template.
- **Scope:** Tar+PGP encryption, local + mount + remote persistence, retention, exit-code-based success/failure.

### Phase 2 — Cloud Upload
- **Status:** Not started.
- **Decisions:** Choose provider & CLI, implement `modules/cloud.sh`, propagate failure codes.

### Phase 3 — Alerting
- **Status:** Not started.
- **Scope:** `notify.sh` module with Telegram primary + email fallback, triggered on failures only.

## 6. Current Progress (2025-11-13)
- Requirements defined, architecture locked, Phase 1 design & script draft completed, config template ready, cron usage defined.
- Pending: Phase 1 testing, Phase 2 provider selection & module, Phase 3 notification module, Obsidian project curation.

## 7. LLM Workflow Notes
Provide this context when collaborating with LLMs to ensure consistent assumptions:
```
lndB 프로젝트 문서를 기반으로 작업 중이다.
이 시스템은 PGP 기반 3-2-1 Zero-Knowledge Backup이며
backup.sh + lndb.conf 구조이며
Phase 1 = local/mount/remote
Phase 2 = cloud
Phase 3 = alerting 순서로 개발한다.
스크립트 언어는 bash이며 Linux 환경(ubuntu/alpine)이 대상이다.
```

Example tasks for LLM assistance include debugging `backup.sh`, writing cloud modules, crafting notification functions, designing cron schedules, documenting GPG best practices, recovery procedures, and test checklists.

## 8. Next Action Items
1. Test Phase 1 script with real LND data and failure scenarios (mount/network/encryption).
2. Select a cloud provider/CLI for Phase 2 and design upload flow.
3. Design Telegram→Email alerting chain (message templates, retries).
4. Store this documentation alongside `/opt/lndb/backup.sh` for Obsidian tracking.

## 9. Testing Checklist
- **Phase 1:** Local backup success, mounted disk enforcement, remote transfer success/failure handling, retention purge, decrypt/restore validation.
- **Phase 2:** CLI auth + upload success/failure handling.
- **Phase 3:** Telegram success, failure detail clarity, email fallback behavior.

## 10. Appendices
- **Recovery Command:** `gpg --decrypt backup-xxxx.tar.gz.gpg | tar xzf -`
- **Critical LND Artifacts:** `channel.db`, macaroon DB, `tls.cert`, `data/chain/<network>/wallet.db`.
