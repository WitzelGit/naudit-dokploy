# naudit-dokploy

Naudit als Compose-Projekt für Dokploy: Image mit `git`-Fix, Compose-Datei,
Environment-Vorlage. Ein Repo, ein Dienst in Dokploy.

## Warum das eigene Image

Das offizielle `ghcr.io/benediktnau/naudit` enthält **kein `git`**. Naudit klont für
Repo-Kontext, Architektur-Profil und SAST-Grounding aber den PR-Stand
(`GitWorkspaceProvider`). Schlägt das fehl, fällt der Review still auf „nur Diff"
zurück — ohne Fehlermeldung, nur eine `warn`-Zeile im Log. Das `Dockerfile` hier
legt genau ein `apt`-Layer mit `git` auf das fertige Image; der Build dauert
Sekunden und kompiliert nichts.

## Einrichtung in Dokploy

1. **Projekt** anlegen → **Create Service** → **Compose**.
2. **Provider** auf dieses Repo zeigen lassen, Branch `main`.
   - **Compose Type:** `Docker Compose` (nicht `Stack` — Swarm-Stacks können
     kein `build:`).
   - **Compose Path:** `./compose.yaml`
3. **Environment** befüllen, Vorlage siehe [`.env.example`](.env.example):

   | Variable | Pflicht | Bedeutung |
   |---|---|---|
   | `NAUDIT_ADMIN_PASSWORD` | ja | Erst-Passwort des WebUI-Admins, mindestens 8 Zeichen |
   | `GITHUB_TOKEN` | ja | Fine-grained PAT: Pull requests RW, Contents R |
   | `GITHUB_WEBHOOK_SECRET` | ja | derselbe Wert wie im GitHub-Webhook |
   | `CLAUDE_CODE_OAUTH_TOKEN` | ja | aus `claude setup-token`, ein Jahr gültig |
   | `NAUDIT_ADMIN_USER` | nein | Vorgabe `admin` |
   | `CLAUDE_MODEL` | nein | Vorgabe `sonnet` |
   | `NAUDIT_VERSION` | nein | Image-Tag, Vorgabe `latest`, z. B. `v0.1.52` |
   | `NAUDIT_MEM_LIMIT` | nein | Vorgabe `3g` |

   Fehlt eine Pflichtvariable, bricht Dokploy den Deploy mit Klartext ab:
   `required variable GITHUB_TOKEN is missing a value: in der Environment-Maske setzen`.

4. **Domains** → Domain anlegen:
   - Host: deine Subdomain
   - **Service Name:** `naudit`
   - **Container Port:** `8080`
   - HTTPS an, Certificate `letsencrypt`
5. **Deploy**.

## Prüfen

Im Log muss stehen:

```
Modus:      Review aktiv
AI:         ClaudeCode · sonnet · Routing: Single …
Now listening on: http://[::]:8080
```

Steht dort `SETUP …`, fehlt eine Pflichtvariable — die Zeile nennt sie.

Dann `https://<deine-domain>/health` → `"healthy"`, und Login mit `admin` und
deinem Passwort.

## Diagnose

Wenn etwas nicht läuft — `check.sh` auf dem Server ausführen:

```bash
./check.sh                              # Container, Netz, Image, Health
./check.sh naudit.deine-domain.de       # zusätzlich von außen
```

Prüft die vier Stellen, an denen es erfahrungsgemäß hakt: läuft der Container,
hängt er am `dokploy-network` (sonst antwortet Traefik mit 502), ist `git` im
Image, und was meldet der Startup-Report.

## Danach: Webhook in GitHub

Repo → Settings → Webhooks → Add webhook:

- Payload URL `https://<deine-domain>/webhook/github`
- Content type `application/json`
- Secret = `GITHUB_WEBHOOK_SECRET`
- Events: **Pull requests** und **Pull request review comments**

Antwortcodes bei der Test-Zustellung: `200` = passt, `401` = Secret stimmt nicht,
`405` = falscher Pfad für die konfigurierte Plattform.

## Bewusste Entscheidungen

- **Benanntes Volume statt Bind-Mount.** Der Container läuft als uid 1654 und kann
  ein root-eigenes Host-Verzeichnis nicht beschreiben — Naudit stirbt dann sofort
  mit `SQLite Error 14: unable to open database file` und startet nicht neu.
- **Kein `ports:`.** Traefik erreicht den Container über `dokploy-network`. Ein
  veröffentlichter Port würde 8080 unverschlüsselt nach außen aufmachen.
- **Healthcheck über `bash` und `/dev/tcp`.** Im Image gibt es weder `curl` noch
  `wget`; die übliche curl-Zeile ließe den Container dauerhaft `unhealthy` wirken.
- **Kein Volume für die `claude`-CLI.** Naudit legt pro Review ein eigenes
  `CLAUDE_CONFIG_DIR` unter `/tmp` an — es gibt keinen CLI-Zustand, der überleben
  müsste.

## Aktualisieren

`Deploy` in Dokploy baut auf dem dann aktuellen `:latest` neu. Für einen
kontrollierten Sprung `NAUDIT_VERSION` auf einen festen Tag setzen.

Dokploys *Auto Deploy* hilft hier nicht: es reagiert auf Pushes in **dieses**
Repo, und das ändert sich praktisch nie.

## Optional: SAST einschalten

Die Scanner (opengrep, trivy, betterleaks, osv-scanner) sind im Image enthalten,
aber aus. Anschalten in der WebUI unter *Settings → Review rules* oder per
Umgebung. Dann in `compose.yaml` das `naudit-cache`-Volume einkommentieren, sonst
lädt Trivy seine Schwachstellen-DB nach jedem Neustart neu.
