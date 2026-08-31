# Service mesh — why sidecar, and what it costs

**Decision: sidecar mode, STRICT mTLS, for as long as the canary depends on
Istio's L7 (layer 7 — the HTTP layer, where a proxy can read paths, methods and
headers) routing.** Ambient mode is the intended destination, not the current
one, and this document records what has to be true before that move is worth
making.

Measured on Istio 1.30.4, GKE 1.35, on 2026-08-31 against the running cluster.

## What the mesh is here for

Two things, both of which would otherwise have to be written into the
application:

- **Encryption in transit between every pod**, with certificate rotation nobody
  maintains. `PeerAuthentication` is `STRICT`, not `PERMISSIVE` — permissive
  accepts plaintext alongside mTLS (mutual TLS — both sides present a
  certificate), which is correct while migrating an existing system into a mesh
  and wrong for a namespace born inside one. Under permissive, "mTLS is on" and
  "mTLS is enforced" stop being the same statement.
- **Authorization written against identity rather than addresses.** The
  namespace is closed by an empty-rule `DENY`, and each opening names a service
  account principal that Envoy verifies from the peer certificate:

  ```
  api    ← cluster.local/ns/app/sa/web                    GET POST PATCH DELETE  /api/*
  redis  ← cluster.local/ns/app/sa/api
  web    ← cluster.local/ns/istio-system/sa/istio-ingressgateway
  ```

  A namespace-scoped rule would let anything in `app` — a debug pod included —
  reach the tier that reaches the database. A principal cannot be spoofed by
  sitting in the right namespace.

## Why not ambient

Ambient mode splits the proxy in two: a per-node `ztunnel` that does L4 (layer 4
— TCP, so mTLS and identity but no knowledge of HTTP), and an opt-in **waypoint**
proxy per namespace or service account that does L7.

Everything in the list above is available at L4 **except** the method-and-path
condition on `api-allow-web` — and, more decisively, the canary. Argo Rollouts
splits traffic here by rewriting `VirtualService` weights, which is an L7
feature. Under ambient that requires a waypoint, so the honest comparison is not
"12 Envoys versus none":

```
sidecar   one Envoy per workload pod
ambient   one ztunnel per node  +  one waypoint per namespace that needs L7
```

The saving is real but it is a change of shape, not an elimination. Adopting
ambient today would mean carrying both the migration and a waypoint, to remove
proxies whose measured cost is below.

## What a sidecar actually costs

Live usage, all three mesh workloads at one replica:

| Pod   | app container | istio-proxy |
|-------|---------------|-------------|
| api   | 1m / 35Mi     | 4m / 38Mi   |
| web   | 1m / 3Mi      | 3m / 42Mi   |
| redis | 7m / 4Mi      | 4m / 49Mi   |

CPU is not the problem — 3–4 millicores is noise. **Memory is the honest number:
each proxy holds 38–49Mi, which is more than two of the three applications it
fronts.** That is the per-pod tax, and it scales with replica count, so it is the
figure to multiply when sizing.

Latency cost, from the recorded in-cluster load test on the paginated build (1
web + 1 api, 25,978 requests, 0.00% failed): p50 9ms, p95 50ms, p99 156ms. Two
proxy hops are inside those numbers and did not stop the tier from reaching
~110 req/s per replica pair.

## The real cost is the request, not the usage

Every injected proxy asks for **100m CPU and 128Mi** and is capped at 2 CPU /
1Gi. Against a measured 3–4m, the request over-reserves by roughly 25×.

That is what fills the scheduler's books while the nodes sit idle. CPU
*requests* already reserved, against the measured usage in the table above:

```
spot / stateless   e2-medium       940m allocatable   611-761m requested (65-80%)
stateful           e2-standard-2  1930m allocatable  1333-1526m requested (69-79%)
```

The application tier runs on the spot pool, and that is where it bites: on a
940m node a single 100m sidecar request is **10.6% of everything schedulable**,
for a proxy observed using 3-4m. Three such pods reserve nearly a third of a node
before an application container is counted.

**Lowering `sidecar.istio.io/proxyCPU` toward the observed usage recovers more
headroom on that pool than switching to ambient would**, and it is a values
change rather than a migration.

Memory should not be cut the same way — 128Mi against a measured 38–49Mi is
about 3× and leaves room for the config a growing mesh pushes into each proxy.

## Native sidecars are already on

The proxy is injected as an `initContainer` with `restartPolicy: Always`, not as
an ordinary container:

```
init=[istio-init:restart=-, istio-proxy:restart=Always]
```

This is Kubernetes' native sidecar support, and it removes the two failure modes
that made sidecars painful historically: the proxy now starts before the
application and shuts down after it, and it no longer keeps a finished `Job`
alive. The k6 load-test Job reaching `Completed` rather than hanging is that
working.

Nothing in the repository asks for this — it is the default at this Istio and
Kubernetes version. Worth knowing, because it is a behaviour we depend on
without declaring.

## Gap: the CNI agent is installed but not wired in

`istio-cni-node` runs on all five nodes, 5/5 ready. Injection does not use it.

Every workload pod still receives the privileged `istio-init` container running
`istio-iptables`, and the injector's own values confirm why:

```
istio_cni: ABSENT
```

istiod was never told the agent exists, so it keeps injecting the init container
that needs `NET_ADMIN` and `NET_RAW`. The point of running the CNI agent is to
move that capability out of every application pod and into one DaemonSet — which
is currently not happening. The chart is deployed, the benefit is not.

Fixing it is a values change on `11-istiod.yaml`, and it needs care: pods
injected while the two sides disagree get no iptables rules at all, and their
traffic silently bypasses the mesh — mTLS that appears to be on and is not.

## What is deliberately outside the mesh

The `database` namespace carries no `istio-injection` label, and that is on
purpose. CloudNativePG runs its own certificate authority and TLS 1.3 between
primary and replicas, and Istio sidecars are named in its documentation as a
known cause of failures. Wrapping a component that already does mTLS in a second
mTLS layer adds a failure mode and no security.

The mesh boundary therefore stops at `api`. `api` → Postgres is encrypted by
CloudNativePG, not by Envoy.

## When to move to ambient

Not on cost. The triggers are:

1. **The canary stops needing Istio's L7 routing** — or a waypoint is being
   deployed anyway for another reason.
2. **Replica count grows enough that 40Mi per pod matters.** At three
   application pods it does not. At thirty it does.
3. **A workload that cannot take a sidecar joins the mesh** — ambient adds pods
   to the mesh without modifying them, which is its other real advantage.

Before any of that, two cheaper wins are available and are not taken: wiring the
CNI agent into injection, and bringing `proxyCPU` down to something near what the
proxies actually use.

One caveat carried forward from the CNI work: ambient on GKE wants
`global.platform=gke`, and that setting has already broken this cluster once.
Under Argo CD the chart is rendered by `helm template`, where `KubeVersion`
carries no `-gke` suffix, so the platform branch produced the wrong
`cniBinDir` — `/opt/cni/bin` instead of GKE's `/home/kubernetes/bin`. Verified by
rendering both locally. Any ambient migration has to render first and read the
output, not assume the chart knows where it is running.
