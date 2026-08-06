---
title: Lesson 16 - Networking Fundamentals and the CNI
module: 04 Networking
lesson: 16
status: Complete
tags: [kubernetes, networking, cni, kube-proxy, iptables, dnat, ipam, ipvs, ebpf]
---

# Lesson 16 - Networking Fundamentals and the CNI

## Table of Contents

- [Learning Objectives](#learning-objectives)
- [Prerequisites](#prerequisites)
- [Real-world Motivation](#real-world-motivation)
- [Core Concepts](#core-concepts)
- [Architecture](#architecture)
- [ASCII Diagrams](#ascii-diagrams)
- [Hands-on](#hands-on)
- [Commands](#commands)
- [YAML Explanation](#yaml-explanation)
- [Production Notes](#production-notes)
- [Best Practices](#best-practices)
- [Common Mistakes](#common-mistakes)
- [Troubleshooting](#troubleshooting)
- [Interview Questions](#interview-questions)
- [Scenario Questions](#scenario-questions)
- [Quiz](#quiz)
- [Revision](#revision)
- [Cheat Sheet](#cheat-sheet)
- [References](#references)
- [Related Lessons](#related-lessons)
- [Coming Next](#coming-next)

---

## Learning Objectives

By the end of this lesson you will be able to:

- Explain how the CNI (Container Network Interface) assigns Pod IPs and routes traffic between nodes.
- Describe how kube-proxy uses iptables to route Service traffic to Pods.
- Inspect the actual Linux iptables rules on a Kubernetes node.
- Explain what happens to network traffic when a Service has no healthy Endpoints (the REJECT rule).

## Prerequisites

- Completion of Lessons 1 through 19.
- A running kind cluster (We will exec into the node's Docker container).
- kubectl installed and configured.

## Real-world Motivation

### The Black Box Network

A user reports a 502 Bad Gateway or a Connection Refused error. You know the Service routes to the Pods, but the network feels like a black box. How did the packet travel? If you don't understand that kube-proxy writes iptables rules, you won't know how to trace a packet from a Service IP to a Pod IP. Furthermore, if you have 10,000 Services, your cluster might suffer from mysterious network latency because the kernel is evaluating 10,000 firewall rules sequentially.

### Why This Exists

Kubernetes required a flat network structure where every Pod can talk to every other Pod without NAT. To achieve this without writing custom networking code, Kubernetes relied on the Linux kernel's battle-tested networking stack (iptables) and offloaded the Pod IP assignment to a standardized plugin interface (CNI). This kept the core Kubernetes codebase small and allowed vendors (Calico, Cilium, Flannel) to innovate.

### Real Company Examples

**DoorDash:** DoorDash outgrew iptables-based kube-proxy. With thousands of microservices, the iptables ruleset became so massive that packet latency spiked. They migrated to Cilium, which uses eBPF to bypass iptables entirely, routing packets directly in the Linux kernel. Network latency dropped significantly.

## Core Concepts

### Explain Like I'm 12

The CNI is the postal service. It builds roads between all the houses (Nodes) and gives every house a unique address (Pod IP).

kube-proxy is the mail sorter. When you send a letter to a "P.O. Box" (Service IP), the mail sorter intercepts it, crosses out the P.O. Box, writes the real house address (Pod IP) on it, and puts it back in the mail.

### Explain Like I'm a Junior Engineer

Kubernetes uses a flat network. The CNI plugin creates a virtual network interface for every Pod and assigns it an IP. It also handles the complex routing tables that allow Pod traffic to cross from Node A to Node B.

Meanwhile, kube-proxy runs on every node. It watches the API Server. When a Service is created, kube-proxy writes iptables rules on the Linux host. When network traffic hits the Service IP, the kernel intercepts it and rewrites the destination to a real Pod IP.

### Explain Technically

- **CNI:** The kubelet calls the CNI binary during Pod creation. The CNI handles IPAM (IP Address Management) and connects the Pod's network namespace to the host.
- **kube-proxy:** In iptables mode (the default), it creates a custom chain for every Service (`KUBE-SVC-XXXX`). It maps the Service IP to this chain. The chain contains rules pointing to Endpoint IPs (`KUBE-SEP-XXXX`).
- **Load Balancing:** kube-proxy uses the `statistic` module in iptables. For a Service with 2 Pods, the rule says: "With 50% probability, jump to SEP-1. Otherwise, jump to SEP-2." The SEP rule performs the DNAT, rewriting the packet to the Pod IP.

### How Kubernetes Implements It Internally

When a client Pod sends a packet to a Service IP, the Linux kernel's `PREROUTING` netfilter hook catches it. It jumps to the `KUBE-SERVICES` chain, finds the match for the Service IP, and jumps to the `KUBE-SVC` chain. The random probability rule selects a `KUBE-SEP` chain. The `KUBE-SEP` chain executes `DNAT --to-destination 10.1.0.5:80`. The packet is then routed normally by the kernel to the Pod.

### Why Kubernetes Was Designed That Way

Kubernetes was designed to use the Linux kernel's existing networking stack. By using iptables (or eBPF), Kubernetes avoids implementing its own packet forwarding. This keeps the core codebase small and allows vendors to innovate with different CNI plugins.

## Architecture

```
[ Pod A ] -> (Sends packet to Service IP 10.96.0.10)
      |
      v
[ Linux Kernel (Node) ]
      |
      v (iptables PREROUTING hook)
[ KUBE-SVC-XXXX Chain ] (Matches Service IP) -> DNAT (Rewrite destination IP)
      |
      v
[ KUBE-SEP-YYYY Chain ] (Selects Pod IP: 10.1.0.5)
      |
      v (Packet now destined for 10.1.0.5)
[ CNI Plugin ] -> Routes packet to Node 2
```

### Terminology

| Term | Definition |
|------|------------|
| CNI | Container Network Interface. The plugin responsible for Pod networking (e.g., Calico, Cilium, Kindnetd). |
| kube-proxy | The component that programs network routing rules on every node. |
| iptables | The Linux kernel firewall framework used by kube-proxy to intercept and rewrite packets. |
| DNAT | Destination Network Address Translation. Changing the destination IP of a packet. |
| IPAM | IP Address Management. The CNI component that assigns unique IPs to Pods. |

### How It Works Internally

1. You create a Deployment with 2 Pods and a Service.
2. The CNI assigns IPs (10.1.0.5, 10.1.0.6) to the Pods.
3. The API Server assigns a virtual ClusterIP (10.96.0.10) to the Service.
4. kube-proxy on Node A notices the Service. It writes an iptables rule: "If destination is 10.96.0.10:80, jump to KUBE-SVC-123".
5. kube-proxy creates `KUBE-SVC-123`: "With 50% probability, jump to KUBE-SEP-A. Else, jump to KUBE-SEP-B".
6. kube-proxy creates `KUBE-SEP-A`: "DNAT to 10.1.0.5:80".
7. A client sends a packet. The kernel evaluates the rules, rewrites the IP, and forwards it.

### Step-by-Step Workflow

1. Developer creates a Service.
2. kube-proxy detects the Service and creates the `KUBE-SVC` chain.
3. EndpointController populates the Service with Pod IPs.
4. kube-proxy detects the Endpoints and creates `KUBE-SEP` chains.
5. Client sends traffic to Service IP.
6. Kernel intercepts, evaluates rules, and rewrites destination to Pod IP.
7. CNI routes the packet to the correct node/Pod.

### Lifecycle

| State | Description |
|-------|-------------|
| Creation | Rules are written to the kernel. |
| Scaling Up | New `KUBE-SEP` rules are added for new Pods. |
| Pod Crash | The EndpointController removes the Pod IP. kube-proxy deletes the `KUBE-SEP` rule instantly. |
| No Endpoints | If all Pods are gone, kube-proxy replaces the `KUBE-SVC` rule with a REJECT rule. |

### kube-proxy Mode Comparison

| kube-proxy Mode | Technology | Performance | Use Case |
|-----------------|------------|-------------|----------|
| iptables | Sequential rule evaluation | O(n) (Slow for 10k+ services) | Default, good for small/medium clusters |
| IPVS | Linux Virtual Server (Hash tables) | O(1) (Fast) | Large clusters with many services |
| eBPF (Cilium) | eBPF programs in kernel | O(1) (Fastest) | Modern clusters, bypasses iptables entirely |

### Common Myths

| Myth | Fact |
|------|------|
| "Kubernetes routes network traffic." | False. The Kubernetes control plane (kube-proxy) only writes the rules. The actual routing is done by the Linux kernel using iptables or eBPF. |
| "If a Service has no Endpoints, traffic times out." | False. kube-proxy writes a REJECT rule, so the kernel instantly sends back a "Connection Refused" error. You only get a Timeout if a Network Policy is silently dropping packets. |

## ASCII Diagrams

Mental Model: The Service IP is a fake address. kube-proxy is a mail forwarder. You send a letter to the fake address. The forwarder intercepts it, scribbles out the fake address, writes the real Pod IP address, and puts it back in the mail.

```
[ Client Pod ]
      | (Sends packet to 10.96.0.10:80)
[ Linux Kernel (Node) ]
      | (iptables PREROUTING hook)
[ KUBE-SVC-XXXX Chain ] (Matches Service IP)
      | (DNAT: Rewrite destination IP)
[ KUBE-SEP-YYYY Chain ] (Selects Pod IP: 10.1.0.5)
      | (Packet now destined for 10.1.0.5)
[ Target Pod ]
```

## Hands-on

### Objective

Inspect the actual iptables rules on a kind node, find the load-balancing rules, and then watch them change when a Pod crashes.

### Step 1: Create a Deployment and Service

```bash
kubectl create deployment net-app --image=nginx:alpine --replicas=2
kubectl expose deployment net-app --port=80 --target-port=80
```

### Step 2: Enter the Node

Because kind runs nodes as Docker containers, we can exec directly into the Kind node to look at the real Linux iptables rules.

```bash
docker exec -it kind-control-plane bash
```

(You are now inside the Linux node itself, not a Pod).

### Step 3: View the iptables Rules

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

### Step 4: Break Things on Purpose

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

### Step 5: Cleanup

Type `exit` to leave the Kind node, then clean up the resources:

```bash
exit
kubectl delete deployment net-app
kubectl delete svc net-app
```

## Commands

```bash
# Enter the Linux node to inspect kernel-level configs
docker exec -it <kind-node> bash

# View iptables rules for a specific service
iptables-save | grep <service-name>

# View all KUBE-SVC chains
iptables-save | grep KUBE-SVC

# View all KUBE-SEP chains
iptables-save | grep KUBE-SEP

# Check kube-proxy mode
kubectl get configmap -n kube-system kube-proxy -o yaml | grep mode
```

## YAML Explanation

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: net-app
spec:
  replicas: 2
  selector:
    matchLabels:
      app: net-app
  template:
    metadata:
      labels:
        app: net-app
    spec:
      containers:
      - name: nginx
        image: nginx:alpine
        ports:
        - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: net-app
spec:
  selector:
    app: net-app
  ports:
  - port: 80
    targetPort: 80
```

### Field-by-Field Explanation

- `Deployment.spec.replicas: 2`: Creates 2 Pods for load balancing.
- `Service.spec.selector.app: net-app`: Routes traffic to Pods with this label.
- `Service.spec.ports[0].port: 80`: The Service listens on port 80.
- `Service.spec.ports[0].targetPort: 80`: Forwards to port 80 on the Pod.

## Production Notes

- **Use IPVS or eBPF for large clusters:** iptables evaluates rules sequentially. If you have 10,000 Services, a packet might traverse 10,000 rules. IPVS uses hash tables (O(1)) and eBPF bypasses iptables entirely.
- **Don't bypass the CNI:** Do not manually configure node network interfaces. Let the CNI manage the routing tables.
- **Monitor kube-proxy:** If kube-proxy crashes, the node's iptables rules become stale. New Services won't route, and dead Pods will still receive traffic.

### When to Use / When NOT to Use

**Use standard iptables kube-proxy when:**

- Most standard workloads and cluster sizes.
- When you want the default, most stable Kubernetes networking stack.

**Avoid iptables when:**

- If you have 5,000+ Services, the kernel CPU usage will spike. Switch to IPVS or install a CNI like Cilium that replaces kube-proxy entirely with eBPF.

### Performance and Security Considerations

**Performance:** iptables is the biggest networking bottleneck in massive Kubernetes clusters. Every packet destined for a Service must traverse the `KUBE-SERVICES` chain. eBPF solves this by evaluating packets directly at the network driver level before they enter the standard Linux network stack.

**Security:** kube-proxy rules are stored in memory. If a node is rebooted, kube-proxy must rebuild all iptables rules from scratch. During this brief window, Services might be unreachable.

## Best Practices

- Understand iptables rules for debugging.
- Use IPVS or eBPF for large clusters.
- Monitor kube-proxy health.
- Don't manually configure node networking.
- Use Network Policies for security.

## Common Mistakes

| Mistake | Why It Happens | How to Avoid It |
|---------|----------------|-----------------|
| Thinking K8s routes packets | Not understanding the kernel's role | The Linux kernel routes packets based on kube-proxy rules |
| Blaming CNI for Service issues | Not checking Endpoints | If Endpoints are empty, kube-proxy correctly rejects traffic |
| Using iptables for 5,000+ services | Not understanding O(n) complexity | Switch to IPVS or eBPF |

## Troubleshooting

**Symptom: 502 Bad Gateway or Connection Refused**

Cause: Service has no Endpoints or kube-proxy out of sync.

```bash
kubectl get endpoints <svc-name>
```

Fix: Ensure Pods match the Service selector and are Running.

**Symptom: kube-proxy not updating rules**

Cause: kube-proxy cannot talk to API Server.

```bash
kubectl logs -n kube-system <kube-proxy-pod>
```

Fix: Check kube-proxy RBAC and API Server connectivity.

**Symptom: Network latency in large clusters**

Cause: iptables rule evaluation is O(n).

```bash
iptables-save | wc -l
```

Fix: Switch to IPVS or eBPF (Cilium).

## Interview Questions

**Q: What is the CNI?**

A: The Container Network Interface. It is a plugin responsible for assigning IP addresses to Pods and configuring the network routing that allows Pods to communicate across different nodes.

**Q: How does kube-proxy route traffic to a Service?**

A: kube-proxy runs on every node and watches the API server. When a Service is created, it programs iptables rules. When a packet is sent to the Service ClusterIP, the kernel intercepts it, performs DNAT (Destination Network Address Translation), rewrites the destination IP to a healthy Pod IP, and forwards it.

**Q: What happens in iptables when a Service has no healthy Endpoints?**

A: kube-proxy deletes the Endpoint rules and writes a REJECT rule, causing instant "Connection Refused" errors.

**Q: Why might a large cluster switch from iptables to IPVS or eBPF for kube-proxy?**

A: iptables evaluates rules sequentially (O(n)). In massive clusters with thousands of services, this adds significant latency. IPVS uses hash tables for O(1) lookups, and eBPF bypasses iptables entirely for even faster routing.

**Q: You have a Service with 2 healthy Pods, but traffic is returning Connection Refused. The Endpoints object is populated. What could be the issue?**

A: If the Endpoints are populated, the EndpointController is working. The issue might be that kube-proxy on the client's node is out of sync or crashed, so the iptables rules haven't been updated. I would check the kube-proxy logs on that node.

**Q: Does Kubernetes route network packets in user-space?**

A: No. It happens in the kernel via iptables/eBPF.

## Scenario Questions

**Scenario 1:** Your Service is returning Connection Refused. How do you diagnose?

A: I would check `kubectl get endpoints <svc>` to see if Pods are matched. If empty, I would check Pod labels. If populated, I would check kube-proxy logs.

**Scenario 2:** You have 10,000 Services and network latency is spiking. What do you do?

A: I would switch kube-proxy to IPVS mode or install Cilium as the CNI, which uses eBPF to bypass iptables entirely.

**Scenario 3 (Mini Project - The IPVS Switch):**

Read the documentation on how to configure kind to use IPVS mode for kube-proxy. Recreate your kind cluster with the `kubeProxyMode: ipvs` configuration. Exec into the node and run `ipvsadm -L`. Compare the IPVS rules to the iptables rules you saw in this lab.

## Quiz

1. What does CNI stand for?
   - A. Container Network Interface
   - B. Core Network Integration
   - C. Cluster Network Isolation
   - D. Container Node Integration

2. What does kube-proxy program on each node?
   - A. DNS records
   - B. iptables rules
   - C. Network Policies
   - D. Service accounts

3. What is DNAT?
   - A. Source Network Address Translation
   - B. Destination Network Address Translation
   - C. Dynamic Network Address Translation
   - D. Direct Network Address Translation

4. What happens when a Service has no Endpoints?
   - A. Traffic times out
   - B. kube-proxy writes a REJECT rule
   - C. Traffic is dropped silently
   - D. Traffic goes to a random Pod

5. What is the default kube-proxy mode?
   - A. IPVS
   - B. eBPF
   - C. iptables
   - D. userspace

Answers: 1-A, 2-B, 3-B, 4-B, 5-C.

## Revision

One-minute revision:

- CNI = Pod IPs + Routing.
- kube-proxy = iptables rules.
- `KUBE-SVC` = Service IP match.
- `KUBE-SEP` = Pod IP (DNAT).
- No Endpoints = REJECT.

Memory trick:

- **CNI:** The road builder. Gives every house (Pod) an address.
- **iptables (`KUBE-SVC`):** The traffic cop at an intersection. "You want to go to the Service IP? Take this lane."
- **iptables (`KUBE-SEP`):** The specific driveway. "Out of 3 houses, randomly pick this one driveway to deliver the package."

Key facts:

- CNI = IP assignment + routing.
- kube-proxy = iptables rules.
- DNAT = Rewrite destination IP.
- No Endpoints = REJECT.
- IPVS/eBPF = O(1) performance.

## Cheat Sheet

| Command | What it does |
|---------|--------------|
| `docker exec -it <kind-node> bash` | Enter the Linux node to inspect kernel-level configs |
| `iptables-save \| grep <service-name>` | View iptables rules for a specific service |

## References

- [Kubernetes Documentation: Service Routing](https://kubernetes.io/docs/concepts/services-networking/service/)
- [Cilium Documentation: eBPF vs iptables](https://docs.cilium.io/en/stable/network/ebpf/)
- [Kubernetes Documentation: kube-proxy](https://kubernetes.io/docs/reference/command-line-tools-reference/kube-proxy/)
- [Linux iptables documentation](https://www.netfilter.org/documentation.html)

## Related Lessons

- [Lesson 17 - Services and Cluster Networking](lesson-17-services-and-cluster-networking.md) - how Services work.
- [Lesson 18 - Ingress and Ingress Controllers](lesson-18-ingress-and-ingress-controllers.md) - exposing applications externally.
- [Lesson 19 - Network Policies](lesson-19-network-policies.md) - micro-segmentation firewalls.

## Coming Next

Now that you understand how CNI and kube-proxy work together, the next lesson covers Services in depth — how to expose your Pods internally and externally.
