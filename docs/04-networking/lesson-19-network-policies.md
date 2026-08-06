---
title: Lesson 19 - Network Policies
module: 04 Networking
lesson: 19
status: Complete
tags: [kubernetes, networking, cni, network-policies, micro-segmentation, security, iptables, ebpf]
---

# Lesson 19 - Network Policies

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

- Explain the "default allow" nature of Kubernetes networking.
- Describe what a CNI (Container Network Interface) is and its role in the cluster.
- Explain what a NetworkPolicy is and how it acts as a firewall.
- Create a Default Deny policy to isolate a namespace.
- Debug a network connection that is being silently dropped (Timeout vs Connection Refused).

## Prerequisites

- Completion of Lessons 1 through 12.
- A running kind cluster (Kind's default CNI, kindnetd, supports Network Policies natively).
- kubectl installed and configured.

## Real-world Motivation

### The Flat Network

Imagine you have a payments namespace and a marketing namespace. By default, Kubernetes uses a flat network structure. Any Pod in the marketing namespace can directly ping the database Pods in the payments namespace. If a hacker compromises a marketing Pod, they can run a network scanner, find the payments database, and brute-force the password. RBAC doesn't help here because the traffic isn't going through the API Server; it's going directly over the virtual network.

### Why This Exists

To achieve PCI compliance or a zero-trust architecture, you must isolate workloads. Network Policies are the Kubernetes-native way to define which Pods are allowed to communicate with each other. They allow you to say, "The frontend Pod can only talk to the backend Pod on port 8080. Block everything else."

### Real Company Examples

**Capital One:** Capital One uses Cilium as their CNI. They enforce strict Network Policies. The frontend Pods can only talk to the backend API Pods on port 443. The backend Pods can only talk to the database Pods on port 5432. If an attacker gets into the frontend, they cannot directly scan the database network; they are trapped in a strict allow-list.

## Core Concepts

### Explain Like I'm 12

Imagine a giant hotel where every guest gets a phone in their room. By default, any guest can pick up the phone and dial any other guest's room directly. There are no locked doors.

A NetworkPolicy is like telling the hotel operator: "My room (Pod) will only accept phone calls from my family (specific labels). Hang up on everyone else."

### Explain Like I'm a Junior Engineer

A NetworkPolicy is a Kubernetes resource (`kind: NetworkPolicy`). It uses label selectors (just like Services and ReplicaSets) to define ingress (incoming) and egress (outgoing) traffic rules. Because the network is Default Allow by default, you must first apply a "Default Deny" policy to a namespace to lock it down, and then create specific "Allow" policies to punch holes for legitimate traffic.

### Explain Technically

- The NetworkPolicy object is stored in etcd.
- The CNI plugin (e.g., Calico) runs an agent on every node. It watches the API Server for NetworkPolicy objects.
- When the CNI sees a policy that selects a Pod, it translates the rules into low-level Linux firewall rules (like iptables, nftables, or eBPF programs) on the specific nodes where the Pods are running.
- When a network packet arrives at a node destined for a Pod, the kernel intercepts it. If a firewall rule says "drop", the packet is silently discarded.

### How Kubernetes Implements It Internally

Kubernetes itself does not enforce Network Policies. The API Server just stores the YAML. It is up to the CNI plugin (like Calico, Cilium, or Kindnetd) to watch for these policies and program the Linux kernel firewall rules. The CNI agent on each node translates the policy into iptables rules or eBPF programs. When a packet arrives, the kernel checks the rules in order. If no rule allows the traffic, the packet is dropped silently.

### Why Kubernetes Was Designed That Way

Kubernetes was designed to be CNI-agnostic. By not embedding the enforcement mechanism into the core, it allows operators to choose the CNI that fits their scale and feature needs. Some CNIs don't support Network Policies at all, while others (like Cilium) support advanced L7 rules.

## Architecture

```
[ Namespace: frontend ]        [ Namespace: backend ]
[ Pod: client (app=web) ]      [ Pod: nginx (app=api) ]
      |                                |
      | (curl http://nginx)            |
      +------------------------------->+
        (Default: Allowed!)
      |                                |
      | (Apply NetworkPolicy)          |
      |                                v
      |                        [ NetworkPolicy: Default Deny Ingress ]
      |                                |
      | (curl http://nginx)            |
      +------------X (Blocked!)--------+
```

### Terminology

| Term | Definition |
|------|------------|
| CNI | Container Network Interface. The plugin responsible for Pod networking (e.g., Calico, Cilium). |
| NetworkPolicy | A Kubernetes API object that defines how a group of Pods are allowed to communicate. |
| Ingress | Incoming network traffic to a Pod. |
| Egress | Outgoing network traffic from a Pod. |
| Default Deny | A state where all traffic to/from a Pod is blocked unless explicitly allowed. |

### How It Works Internally

1. You apply a NetworkPolicy with `podSelector: {}` (meaning select all Pods) and `policyTypes: [Ingress]` (with no ingress rules defined).
2. The CNI agent on Node A notices the policy.
3. It writes an iptables rule: "If the destination is a Pod on this node, and the source is not explicitly allowed, DROP the packet."
4. A client Pod sends a curl request.
5. The packet reaches Node A. The kernel matches the iptables rule.
6. The kernel drops the packet into the void. It does not send a "Connection Refused" response back.
7. The client Pod waits for a response. Eventually, it gives up with a "Timeout".

### Step-by-Step Workflow

1. Developer creates a Namespace with 2 Pods.
2. Developer verifies Pod A can ping Pod B.
3. Developer applies a default-deny NetworkPolicy to the Namespace.
4. The CNI updates the kernel firewall rules.
5. Developer tries to ping Pod B again. The connection hangs and eventually times out.
6. Developer applies a second `allow-web` NetworkPolicy permitting traffic from Pod A.
7. The CNI updates the rules to allow Pod A's IP.
8. Ping succeeds.

### Lifecycle

| State | Description |
|-------|-------------|
| Creation | Policy is created. CNI agents update their node firewalls. |
| Pod Addition | If a new Pod is created that matches the policy's selector, the CNI instantly applies the firewall rules to it. |
| Deletion | Policy is deleted. The network reverts to Default Allow for those Pods. |

### CNI Plugin Comparison

| CNI Plugin | Technology | NetworkPolicy Support |
|------------|------------|----------------------|
| Kindnetd | iptables | Yes (Basic) |
| Calico | iptables / eBPF | Yes (Advanced) |
| Cilium | eBPF | Yes (Advanced, L7 capable) |
| Flannel | - | No (Requires Calico addon) |

### Common Myths

| Myth | Fact |
|------|------|
| "If I put my database in a separate namespace, it is isolated." | False. Namespaces are a logical grouping, not a network boundary. By default, Pod A in Namespace X can ping Pod B in Namespace Y. You need a NetworkPolicy to create a network boundary. |
| "Services provide security." | False. Services are just load balancers. They do not block traffic. Only Network Policies secure traffic. |

## ASCII Diagrams

Mental Model: Kubernetes networking is a wide-open field. A NetworkPolicy is a concrete bunker. If you put a Pod in a bunker with no doors, nobody can get in. You must explicitly cut a hole in the bunker (ingress rule) for specific people to enter.

```
[ Client Pod ]
      |
      v (Sends packet to 10.244.1.5:80)
[ Linux Kernel (Node) ]
      |
      v (iptables / eBPF hook)
[ CNI Firewall Rules ] (Checks NetworkPolicies)
      |
      +---> (Policy: Default Deny Ingress) -> DROP PACKET (Client gets Timeout)
```

## Hands-on

### Objective

Create two namespaces, prove they can talk, and then lock down the backend namespace with a Default Deny policy.

### Step 1: Create Namespaces and Deploy Pods

```bash
kubectl create namespace frontend
kubectl create namespace backend

kubectl run web --image=nginx:alpine -n backend -l app=api
kubectl run client --image=alpine -n frontend -l app=web -- sleep 3600
```

Wait for the `web` pod in the backend namespace to be Running.

### Step 2: Prove Default Connectivity

Get the IP of the web pod:

```bash
kubectl get pod web -n backend -o wide
# Note the IP address, e.g., 10.244.1.5
```

Exec into the client pod and try to reach it:

```bash
kubectl exec -it client -n frontend -- sh
# Inside the pod:
wget -qO- http://10.244.1.5
```

You should see the standard Nginx "Welcome to nginx!" HTML output. Traffic flows freely by default.

Type `exit`.

### Step 3: Apply a Default Deny NetworkPolicy

Create `deny-all.yaml`:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-ingress
  namespace: backend
spec:
  podSelector: {}
  policyTypes:
  - Ingress
```

**Field Explanation:**

- `namespace: backend`: This policy only affects Pods in the backend namespace.
- `podSelector: {}`: An empty selector means "select ALL pods in this namespace".
- `policyTypes: - Ingress`: We are controlling incoming traffic.
- (No ingress rules defined): Because we specified Ingress but gave it no rules, it becomes an implicit Deny All for incoming traffic.

Apply it:

```bash
kubectl apply -f deny-all.yaml
```

### Step 4: Investigate the Block

Exec back into the client pod:

```bash
kubectl exec -it client -n frontend -- sh
# Inside the pod:
wget -qO- http://10.244.1.5
```

Wait for it... it will hang. Press Ctrl+C to stop it after a few seconds.

**Your Task:**

- What happened when you tried to wget the web pod after applying the policy?
- Did it fail instantly (Connection Refused) or did it hang (Timeout)?
- Based on how a CNI implements Network Policies (e.g., dropping packets), explain why it behaved this way.

(Answer: 1. It hung. 2. Timeout. 3. The CNI inserted iptables rules to DROP the packet. It does not send a rejection response back to the client, so the client waits for an acknowledgement until it times out).

### Step 5: Cleanup

```bash
kubectl delete networkpolicy default-deny-ingress -n backend
kubectl delete namespace frontend backend
```

## Commands

```bash
# List all Network Policies across all namespaces
kubectl get networkpolicy -A

# Describe a specific Network Policy
kubectl describe networkpolicy <name>

# Test internal connectivity from inside a Pod
kubectl exec <pod> -- wget -O- <ip>

# Test connectivity using kubectl exec
kubectl exec -it <pod> -- sh -c "wget -qO- http://<ip>"

# Check which namespace a Pod is in
kubectl get pod <name> -o jsonpath='{.metadata.namespace}'
```

## YAML Explanation

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-ingress
  namespace: backend
spec:
  podSelector: {}
  policyTypes:
  - Ingress
```

### Field-by-Field Explanation

- `apiVersion: networking.k8s.io/v1`: The NetworkPolicy API group.
- `kind: NetworkPolicy`: Defines a network policy resource.
- `metadata.name`: The name of the policy.
- `metadata.namespace`: The namespace this policy applies to.
- `spec.podSelector`: Selects which Pods this policy applies to. `{}` selects all Pods.
- `spec.policyTypes`: The traffic directions this policy controls. `Ingress` controls incoming traffic. `Egress` controls outgoing traffic.

## Production Notes

- **Default Deny Egress is dangerous:** If you block all outgoing traffic, your Pods won't be able to talk to CoreDNS (port 53) to resolve Service names. If you use Egress policies, always allow DNS to kube-system.
- **Don't rely on Services for security:** A Service load-balances traffic, but it does not secure it. Secure the Pods using NetworkPolicies.
- **Use Cilium for scale:** In massive clusters, iptables-based CNI plugins become slow because they evaluate rules linearly. Use an eBPF-based CNI like Cilium for O(1) network policy enforcement.

### When to Use / When NOT to Use

**Use Network Policies when:**

- Multi-tenant clusters where teams must be isolated.
- PCI/HIPAA compliance requiring micro-segmentation.
- Zero-trust security architectures.

**Avoid strict policies when:**

- In early development/local dev clusters where the complexity of debugging firewall rules slows down feature development.
- If your CNI does not support them (the YAML will apply but do nothing).

### Performance and Security Considerations

**Performance:** iptables evaluates rules sequentially. If you have 1,000 NetworkPolicies, a packet might have to traverse 1,000 rules before being dropped. This adds network latency. eBPF (Cilium) solves this with hash maps for O(1) lookups.

**Security:** NetworkPolicies are L3/L4 (IP and Port). If you want to block specific HTTP paths (e.g., allow `/api` but block `/admin`), standard NetworkPolicies can't do it. You need an L7 CNI (Cilium) or a Service Mesh (Istio).

## Best Practices

- Always apply a Default Deny policy in production namespaces.
- Allow DNS (port 53) when using Egress policies.
- Use label selectors consistently across Services and NetworkPolicies.
- Test NetworkPolicies with `kubectl exec` and `wget` or `curl`.
- Use Cilium for advanced L7 policies and better performance.
- Monitor Network Policy changes with audit logs.

## Common Mistakes

| Mistake | Why It Happens | How to Avoid It |
|---------|----------------|-----------------|
| Forgetting DNS | Applying a Default Deny Egress policy and breaking CoreDNS resolution | Always allow DNS to kube-system when using Egress policies |
| Thinking K8s enforces policies | If CNI doesn't support NetworkPolicies, the API Server accepts YAML but does nothing | Verify your CNI supports Network Policies before relying on them |
| Confusing Timeout with Connection Refused | Timeout = firewall drop, Connection Refused = app not listening | Check if a NetworkPolicy is dropping packets before debugging the app |

## Troubleshooting

**Symptom: 502 Bad Gateway or App Hang after applying NetworkPolicies**

Cause: NetworkPolicy is blocking legitimate traffic.

```bash
kubectl get networkpolicy -A
kubectl describe networkpolicy <name>
```

Fix: Review the policy's podSelector and ingress/egress rules. Ensure legitimate traffic is allowed.

**Symptom: DNS resolution fails after applying Egress policy**

Cause: Egress policy blocked port 53 to CoreDNS.

```bash
kubectl exec -it <pod> -- nslookup kubernetes.default.svc
```

Fix: Add an Egress rule allowing UDP/TCP port 53 to the kube-system namespace.

**Symptom: NetworkPolicy YAML applies but traffic still flows**

Cause: CNI doesn't support Network Policies.

```bash
kubectl get pods -n kube-system | grep -i calico
kubectl get pods -n kube-system | grep -i cilium
```

Fix: Install a CNI that supports Network Policies (Calico, Cilium).

## Interview Questions

**Q: By default, can a Pod in Namespace A talk to a Pod in Namespace B?**

A: Yes. Kubernetes uses a flat network by default. Any Pod can reach any Pod unless restricted by a Network Policy.

**Q: Does Kubernetes enforce Network Policies itself?**

A: No. The API Server stores them, but the CNI plugin (like Calico, Cilium, or Kindnetd) must implement and enforce them in the Linux kernel.

**Q: What is the difference between a "Connection Refused" error and a "Timeout" in K8s networking?**

A: "Connection Refused" means the network route worked, but the port is closed (no app listening). A "Timeout" usually means a firewall (Network Policy) is silently dropping the packets, so the client never receives a response.

**Q: You applied a Default Deny Egress policy to your application namespace. Now your applications are failing to start with DNS errors. Why?**

A: The Default Deny policy blocked all outgoing traffic, including DNS requests to CoreDNS in the kube-system namespace. I need to add an Egress rule allowing UDP/TCP port 53 to the kube-system namespace so the Pods can resolve Service names.

**Q: Can NetworkPolicies block traffic based on HTTP URL paths?**

A: No. Standard NetworkPolicies are L3/L4 (IP and Port). To block specific HTTP paths (like `/api` vs `/admin`), you need an L7 CNI like Cilium or a Service Mesh like Istio.

**Q: What happens to existing Pods when you apply a NetworkPolicy that selects them?**

A: The CNI plugin instantly applies the firewall rules to the selected Pods. Any traffic that doesn't match an allow rule is immediately dropped.

## Scenario Questions

**Scenario 1:** You have a frontend Pod that needs to talk to a backend Pod on port 8080. How do you secure this?

A: I would apply a Default Deny Ingress policy to the backend namespace. Then I would create a second NetworkPolicy that allows ingress traffic from Pods with label `app=frontend` on port 8080.

**Scenario 2:** Your application Pods are failing to start with DNS errors after you applied an Egress policy. How do you fix this?

A: I would add an Egress rule to allow UDP/TCP port 53 to the kube-system namespace so the Pods can resolve Service names.

**Scenario 3 (Mini Project - The Allow-List):**

Create a default-deny policy in the backend namespace. Write a second NetworkPolicy that allows traffic only from Pods with the label `app=web` in the frontend namespace. Test it from the frontend namespace (should work). Deploy a fake pod in a marketing namespace and test it (should timeout).

## Quiz

1. What is the default networking behavior in Kubernetes?
   - A. Default Deny
   - B. Default Allow
   - C. Depends on CNI
   - D. Depends on namespace

2. What does CNI stand for?
   - A. Container Network Interface
   - B. Core Network Integration
   - C. Cluster Network Isolation
   - D. Container Node Integration

3. What happens when you apply a NetworkPolicy with no ingress rules?
   - A. All traffic is allowed
   - B. Only ingress traffic is blocked
   - C. All incoming traffic is denied
   - D. Nothing happens

4. What is the difference between Ingress and Egress?
   - A. Ingress is outgoing, Egress is incoming
   - B. Ingress is incoming, Egress is outgoing
   - C. They are the same
   - D. Ingress is for Services, Egress is for Pods

5. Why might a NetworkPolicy YAML apply but not work?
   - A. The CNI doesn't support Network Policies
   - B. The namespace is wrong
   - C. The podSelector is incorrect
   - D. The API Server is down

Answers: 1-B, 2-A, 3-C, 4-B, 5-A.

## Revision

One-minute revision:

- Default: Allow all.
- Policy applied: Deny all (except allowed).
- Timeout = Firewall drop.
- Connection Refused = App down.
- Don't block DNS!

Memory trick:

- CNI: The road builder.
- NetworkPolicy: A concrete bunker. Put a Pod inside, and it's blind to the world unless you cut a hole (allow rule) in the wall.

Key facts:

- CNI builds the network roads.
- NetworkPolicies are firewalls.
- Default is Allow.
- Default Deny locks it down.
- Timeout = drop.

## Cheat Sheet

| Command | What it does |
|---------|--------------|
| `kubectl get networkpolicy -A` | Lists all Network Policies across all namespaces |
| `kubectl describe networkpolicy <name>` | Shows the exact ingress/egress rules |
| `kubectl exec <pod> -- wget -O- <ip>` | Tests internal connectivity |

## References

- [Kubernetes Documentation: Network Policies](https://kubernetes.io/docs/concepts/services-networking/network-policies/)
- [Kubernetes Documentation: CNI](https://kubernetes.io/docs/concepts/extend-kubernetes/compute-storage-net/network-plugins/)
- [Calico Documentation](https://docs.tigera.io/calico/latest/about/)
- [Cilium Documentation](https://docs.cilium.io/)

## Related Lessons

- [Lesson 16 - Networking Fundamentals and the CNI](lesson-16-networking-fundamentals-and-the-cni.md) - CNI plugins and Pod networking.
- [Lesson 17 - Services and Cluster Networking](lesson-17-services-and-cluster-networking.md) - how Services work.
- [Lesson 18 - Ingress and Ingress Controllers](lesson-18-ingress-and-ingress-controllers.md) - exposing applications externally.
- [Lesson 27 - RBAC and Service Accounts](../07-security/lesson-27-rbac-and-service-accounts.md) - API Server security.

## Coming Next

Now that you understand how to secure traffic between Pods, the next module covers Storage — how to persist data in Kubernetes using Volumes, Persistent Volumes, and Storage Classes.
