# Lab 44 - Centralized Logging (Loki and Promtail)

## Prerequisite

- Completion of [Lesson 44 - Centralized Logging](../docs/08-observability/lesson-44-centralized-logging-loki-and-promtail.md).
- A running kind cluster.
- kubectl and helm installed.

## Objective

Install Loki, Promtail, and a Grafana pre-configured with a Loki datasource, then hunt a specific error log with LogQL.

## Estimated Time

20 minutes.

---

## Step 1: Install the stack

```bash
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update
helm install loki grafana/loki --namespace loki --create-namespace --set service.type=ClusterIP
helm install promtail grafana/promtail --namespace loki
helm install my-grafana grafana/grafana --namespace loki \
  --set admin.user=admin --set admin.password=admin \
  --set datasources."datasources\.yaml".apiVersion=1 \
  --set datasources."datasources\.yaml".datasources[0].name=Loki \
  --set datasources."datasources\.yaml".datasources[0].type=loki \
  --set datasources."datasources\.yaml".datasources[0].url=http://loki:3100 \
  --set datasources."datasources\.yaml".datasources[0].access=proxy
kubectl get pods -n loki -w
```

Expected: after a couple of minutes `loki`, `promtail-*` (a DaemonSet), and `my-grafana` are all `Running`.

## Step 2: Explore self logs

```bash
kubectl port-forward svc/my-grafana 3000:80 -n loki
```

Open `http://localhost:3000` (admin/admin). Go to Explore (compass icon), select the Loki data source, and run:

```logql
{namespace="loki"}
```

Expected: logs from the Loki and Promtail pods.

## Step 3: Deploy an error-generating Pod

```bash
kubectl run error-generator --image=busybox:latest \
  --restart=Never -- sh -c "while true; do echo 'ERROR: Database connection lost!'; sleep 5; done"
```

## Step 4: Find the error in Loki

In Grafana Explore run:

```logql
{namespace="default"} |= "ERROR"
```

Expected: the `ERROR: Database connection lost!` lines stream in from the `error-generator` pod.

## Step 5: Inspect Promtail targets

```bash
kubectl port-forward svc/loki-promtail 9080:9080 -n loki
```

Open `http://localhost:9080/targets`. Expected: the local node shows as a target with active log discovery.

## Verification

```bash
kubectl logs error-generator
```

Expected: matches the same `ERROR: Database connection lost!` lines you found in Grafana, confirming Promtail delivered them.

## Cleanup

```bash
# Ctrl+C in the two port-forward terminals
kubectl delete pod error-generator
helm uninstall loki -n loki
helm uninstall promtail -n loki
helm uninstall my-grafana -n loki
kubectl delete namespace loki
```

## Summary

You stood up a full Loki + Promtail + Grafana logging stack, verified Promtail shipped node logs, and located a specific error using a LogQL filter across the cluster.