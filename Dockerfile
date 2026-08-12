# Naudit + git.
#
# Das offizielle Image bringt kein git mit, Naudit braucht es aber: fuer den
# Repo-Kontext, das Architektur-Profil und das SAST-Grounding klont es den
# PR-Stand flach in ein Temp-Verzeichnis (GitWorkspaceProvider). Schlaegt das
# fehl, faellt der Review still auf "nur Diff" zurueck - ohne Fehlermeldung.
#
# Version bewusst pinnen statt :latest, wenn du kontrolliert aktualisieren
# willst: --build-arg NAUDIT_VERSION=v0.1.52
ARG NAUDIT_VERSION=latest
FROM ghcr.io/benediktnau/naudit:${NAUDIT_VERSION}

USER root
RUN apt-get update \
 && apt-get install -y --no-install-recommends git ca-certificates \
 && rm -rf /var/lib/apt/lists/*

# Zurueck auf den non-root-User des Basis-Images (uid 1654).
USER $APP_UID
