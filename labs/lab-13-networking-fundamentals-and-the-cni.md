# Lab 13 - Networking Fundamentals and the CNI

## Prerequisite

- Completion of [Lesson 13 - Networking Fundamentals and the CNI](../docs/04-networking/lesson-13-networking-fundamentals-and-the-cni.md).
- A running kind cluster.
- kubectl installed and configured.

## Objective

Inspect the actual iptables rules on a kind node, find the load-balancing rules, and then watch them change when a Pod crashes.

## Estimated Time

15 minutes.

---

## Step 1: Create a Deployment and Service

```bash
kubectl create deployment net-app --image=nginx:alpine --replicas=2
kubectl expose deployment net-app --port=80 --target-port=80
```

## Step 2: Enter the Node

Because kind runs nodes as Docker containers, we can exec directly into the Kind node to look at the real Linux iptables rules.

```bash
docker exec -it kind-control-plane bash
```

(You are now inside the Linux node itself, not a Pod).

## Step 3: View the iptables Rules

Let's look at the NAT (Network Address Translation) table and filter for our service.

(Note: kind images might not have iptables installed by default. If so, run `apt-get update && apt-get install -y iptables` first).

```bash
iptables-save | grep net-app
```

Expected output: You will see several chains like `KUBE-SVC-XXXX` and `KUBE-SEP-YYYY`.

Look closely at the output. You will see a rule that looks like this:

```
-A KUBE-SVC-... -m statistic --mode random --probability 0.50000000000 -j KUBE-SEP-...
```

This is kube-proxy load balancing! It says, "With 50% probability, send the packet to SEP (Service Endpoint) 1. Otherwise, send it to SEP 2."

## Step 4: Break Things on Purpose

Keep your shell open in the Kind node. Open a second terminal on your Ubuntu host.

Scale the deployment to 0 replicas:

```bash
kubectl scale deployment net-app --replicas=0
```

Back in the Kind node terminal, run the iptables command again:

```bash
iptables-save | grep net-app
```

**Your Task:**

- After scaling to 0, what happened to the `KUBE-SEP` (Service Endpoint) rules in the iptables output?
- What new rule replaced the old ones? (Look for a rule that says `has no endpoints`).
- Based on how kube-proxy works, what happens to the packets now if a client tries to send traffic to the Service IP?

(Answer: 1. The KUBE-SEP rules were deleted. 2. A rule was added: `-A KUBE-SERVICES -d 10.96.x.x/32 ... -j REJECT --reject-with icmp-port-unreachable`. 3. The kernel matches the REJECT rule and instantly sends back an ICMP port-unreachable message. The client gets a "Connection Refused" error instantly, rather than a timeout).

## Step 5: Cleanup

Type `exit` to leave the Kind node, then clean up the resources:

```bash
exit
kubectl delete deployment net-app
kubectl delete svc net-app
```

---

## What You Learned

- The CNI is the postal service. It creates virtual interfaces (eth0) for Pods and handles IPAM and routing between nodes.
- kube-proxy is the mail sorter. It runs on every node and writes iptables rules.
- When a Service is created, kube-proxy writes `KUBE-SVC` and `KUBE-SEP` chains to perform DNAT.
- If a Service has no Endpoints, kube-proxy writes a REJECT rule so traffic fails instantly.

## Next Steps

Proceed to [Lesson 14 - Services and Cluster Networking](../docs/04-networking/lesson-14-services-and-cluster-networking.md) to learn about Services in depth.

---

[Back to Labs](README.md)
