# Longhorn — RWX shared storage

Longhorn provides the `ReadWriteMany` StorageClass this cluster needs for shared
user content (uploads visible to every web/api replica).

It is NOT used for PostgreSQL. CloudNativePG gives each instance its own
ReadWriteOnce volume and handles replication itself — putting Postgres on a
shared NFS-backed volume invites locking and fsync problems, and is the wrong
tool regardless of cloud.

GKE's default `pd-balanced` StorageClass is ReadWriteOnce: a volume attaches to
one node at a time, so two replicas landing on different nodes leave the second
stuck in FailedAttachVolume. That is the gap Longhorn fills here.

Longhorn over Filestore (GCP managed NFS) on purpose: it runs on any cluster, so
the same manifests work on GKE today and on a local k3d cluster when the trial
credit runs out.
