# PostgreSQL — CloudNativePG

A CloudNativePG cluster, each instance on its own ReadWriteOnce PVC, replication
handled by the operator rather than by shared storage.

Deliberately self-hosted rather than Cloud SQL: the same manifests then run on
GKE, on a local k3d cluster, or anywhere else, which is what keeps this project
alive after the trial credit expires. The managed-database counterpart is RDS in
the author's aws-3tier project — same application, two different data strategies.
