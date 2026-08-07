---
title: Lesson 35 - Building a 3-Tier Web Application
module: 12 Production
lesson: 35
status: Complete
tags: [kubernetes, production, 3-tier, architecture, services, coreDNS, configmaps, secrets, debugging]
---

# Lesson 35 - Building a 3-Tier Web Application

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

- Explain the architecture of a 3-tier application in Kubernetes.
- Deploy a Database tier, a Backend API tier, and a Frontend Web tier.
- Wire them together using Kubernetes Services and CoreDNS.
- Inject configuration using ConfigMaps and Secrets.
- Debug DNS resolution failures between tiers (NXDOMAIN).

## Prerequisites

- Completion of Lessons 1 through 23.
- A running kind cluster.
- kubectl installed and configured.

## Real-world Motivation

### The Disconnected Microservices

Imagine you deploy a frontend web server. It is supposed to fetch data from a backend API. You hardcode the backend Pod's IP address (10.1.0.5) into the frontend's configuration.

- The backend Pod crashes. The ReplicaSet recreates it with a new IP (10.1.0.9).
- The frontend doesn't know about the new IP. It tries to send traffic to 10.1.0.5. The connection times out. Users see 502 Bad Gateway errors.

Furthermore, how does the backend securely authenticate to the database without hardcoding the password into its Docker image?

### Why This Exists

Kubernetes was designed for microservice architectures. To wire them together securely and reliably, Kubernetes provides Services (for stable DNS names) and ConfigMaps/Secrets (for externalized configuration). This decouples the applications from each other, allowing them to scale and restart independently without breaking the system.

### Real Company Examples

**Airbnb:** Airbnb's frontend Next.js apps talk to a backend API gateway. The gateway routes requests to dozens of microservices (e.g., "Listing Service", "Booking Service"). Each microservice has its own Deployment and Service. The Booking Service connects to a PostgreSQL database. The entire flow is managed by Kubernetes Services and DNS resolution.

## Core Concepts

### Explain Like I'm 12

Imagine a restaurant.

- The Frontend is the Waiter. They take your order and bring you the food.
- The Backend is the Chef. They receive the order from the Waiter, figure out what ingredients are needed, and cook the meal.
- The Database is the Pantry. The Chef goes to the Pantry to get the ingredients.

If the Waiter can't find the Chef, or the Chef can't find the Pantry, the restaurant stops working.

### Explain Like I'm a Junior Engineer

A 3-tier app is deployed as three separate components. Each tier has its own ClusterIP Service. The Frontend talks to the `backend-svc` DNS name. The Backend talks to the `db-svc` DNS name. The Backend gets its DB credentials from a Secret. This allows each tier to be scaled and restarted independently.

### Explain Technically

- **Frontend:** A web server (Nginx) serving static HTML/JS. Exposed via a Service.
- **Backend:** An API server. It connects to the DB using a Secret (for credentials) and a Service DNS name (for routing).
- **Database:** A data store (Redis/Postgres). Exposed via a Service.
- **CoreDNS:** When the Backend Pod boots up and tries to connect to `db-svc.default.svc.cluster.local`, the Pod's `resolv.conf` points to CoreDNS. CoreDNS resolves the Service name to the Service's ClusterIP. kube-proxy then routes the traffic to the actual DB Pod.

### How Kubernetes Implements It Internally

Each tier is a separate controller loop. The Frontend Deployment doesn't know about the Backend Deployment. They are completely decoupled. The only thing binding them together is the DNS name specified in their configuration files or environment variables. CoreDNS watches the API Server for Services and creates A-records automatically.

### Why Kubernetes Was Designed That Way

Kubernetes was designed to support microservice architectures. By using Services and DNS, applications can find each other without hardcoding IP addresses. This allows tiers to scale, restart, and fail independently without breaking the system.

## Architecture

```
[ User ]
    | (Port-Forward to frontend-web)
   v
[ Frontend Pod (Nginx) ] <-- serves index.html
   | (wget backend-api)
   v
[ Backend API Service ] (ClusterIP)
   |
   v
[ Backend Pod (Busybox) ] <-- runs a loop checking DB
   | (nc redis-db 6379)
   v
[ DB Service ] (ClusterIP)
   |
   v
[ Database Pod (Redis) ]
```

### Terminology

| Term | Definition |
|------|------------|
| 3-Tier App | An architecture separating UI, API, and Data. |
| Service Discovery | The mechanism by which services find each other (usually via DNS). |
| CoreDNS | The default DNS server in Kubernetes that resolves Service names to ClusterIPs. |
| NXDOMAIN | DNS response for a non-existent domain (e.g., a typo in a service name). |

### How It Works Internally

1. The Frontend Pod tries to `curl http://backend-api`.
2. The Pod's OS checks `/etc/resolv.conf`, which points to CoreDNS.
3. CoreDNS looks up `backend-api.default.svc.cluster.local`.
4. CoreDNS finds the Service `backend-api` and returns its ClusterIP (e.g., 10.96.0.20).
5. The Frontend sends the packet to 10.96.0.20.
6. kube-proxy intercepts the packet, rewrites the destination IP to the Backend Pod's IP, and forwards it.

### Step-by-Step Workflow

1. Developer creates the Database Deployment and Service (`db-svc`).
2. Developer creates a Secret containing the DB password.
3. Developer creates the Backend Deployment. It reads the Secret and connects to `db-svc`.
4. Developer creates the Backend Service (`backend-svc`).
5. Developer creates the Frontend Deployment. It connects to `backend-svc`.

### Lifecycle

| State | Description |
|-------|-------------|
| Creation | DB -> Secret -> Backend -> Backend Service -> Frontend -> Frontend Service. |
| Scaling | Any tier can be scaled independently. |
| Failure | If the DB crashes, the Backend's health checks fail, but the Frontend stays up (showing an error message to users). |

### Communication Patterns

| Communication | Mechanism | Example |
|---------------|-----------|---------|
| Frontend -> Backend | HTTP via Service DNS | `curl http://backend-api` |
| Backend -> Database | TCP via Service DNS + Secret | `connect(host='db-svc', password=env.secret)` |
| External -> Frontend | Ingress / LoadBalancer | `http://myapp.com` -> Ingress -> Frontend Svc |

### Common Myths

| Myth | Fact |
|------|------|
| "The Frontend Pod needs to be in the same namespace as the Backend Pod." | False. The Frontend can talk to a Backend in another namespace using the fully qualified domain name (FQDN): `backend-api.other-namespace.svc.cluster.local`. |

## ASCII Diagrams

Mental Model: A relay race. The Frontend hands the baton to the Backend Service, which hands it to the Backend Pod, which hands it to the DB Service, which hands it to the DB Pod.

```
[ Frontend ] --(HTTP GET /api)--> [ backend-svc ] --(DNAT)--> [ Backend Pod ]
                                                                        |
                                                                        +--(TCP 6379)--> [ db-svc ] --(DNAT)--> [ DB Pod ]
```

## Hands-on

### Objective

Deploy a 3-tier application (Redis DB, Busybox Backend, Nginx Frontend). Wire them together and debug a DNS failure.

### Step 1: Create the Database Tier

Create `db-tier.yaml`:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: db-secret
type: Opaque
stringData:
  redis-password: "supersecret123"
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: redis-db
spec:
  replicas: 1
  selector:
    matchLabels:
      app: db
  template:
    metadata:
      labels:
        app: db
    spec:
      containers:
      - name: redis
        image: redis:alpine
        env:
        - name: REDIS_PASSWORD
          valueFrom:
            secretKeyRef:
              name: db-secret
              key: redis-password
---
apiVersion: v1
kind: Service
metadata:
  name: redis-db
spec:
  selector:
    app: db
  ports:
  - port: 6379
```

Apply it:

```bash
kubectl apply -f db-tier.yaml
```

### Step 2: Create the Backend Tier

Create `backend-tier.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: backend-api
spec:
  replicas: 1
  selector:
    matchLabels:
      app: backend
  template:
    metadata:
      labels:
        app: backend
    spec:
      containers:
      - name: backend
        image: busybox:latest
        command: ["sh", "-c", "while true; do echo 'Backend: Checking DB...'; nc -z -w2 redis-db 6379 && echo 'Backend: DB is reachable!' || echo 'Backend: DB unreachable'; sleep 5; done"]
---
apiVersion: v1
kind: Service
metadata:
  name: backend-api
spec:
  selector:
    app: backend
  ports:
  - port: 80
```

Apply it:

```bash
kubectl apply -f backend-tier.yaml
```

### Step 3: Create the Frontend Tier

Create `frontend-tier.yaml`:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: frontend-config
data:
  index.html: |
    <html><body><h1>Welcome to the Frontend!</h1><p>Try connecting to the backend API.</p></body></html>
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: frontend-web
spec:
  replicas: 1
  selector:
    matchLabels:
      app: frontend
  template:
    metadata:
      labels:
        app: frontend
    spec:
      containers:
      - name: nginx
        image: nginx:alpine
        volumeMounts:
        - name: config-volume
          mountPath: /usr/share/nginx/html
      volumes:
      - name: config-volume
        configMap:
          name: frontend-config
---
apiVersion: v1
kind: Service
metadata:
  name: frontend-web
spec:
  selector:
    app: frontend
  ports:
  - port: 80
```

Apply it:

```bash
kubectl apply -f frontend-tier.yaml
```

### Step 4: Verify the Connections

Wait for all pods to be Running.

Check the Backend logs to see if it successfully found the Database:

```bash
kubectl logs -l app=backend --tail=5
```

(You should see "Backend: DB is reachable!").

Now, verify the Frontend can talk to the Backend. Exec into the Frontend:

```bash
kubectl exec -it deploy/frontend-web -- sh
```

Inside the Frontend container, run:

```sh
wget -qO- http://backend-api
```

(You will get a Connection refused error. Why? Because the Backend is a busybox netcat loop, not a web server. But it proves DNS routing worked! It found the Backend Pod, it just rejected the HTTP request).

Type `exit`.

### Step 5: Break Things on Purpose

Apply a broken backend with a typo in the DB name:

```bash
cat <<EOF > broken-backend.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: backend-api
spec:
  replicas: 1
  selector:
    matchLabels:
      app: backend
  template:
    metadata:
      labels:
        app: backend
    spec:
      containers:
      - name: backend
        image: busybox:latest
        command: ["sh", "-c", "while true; do echo 'Backend: Checking DB...'; nc -z -w2 redis-database 6379 && echo 'Backend: DB is reachable!' || echo 'Backend: DB unreachable'; sleep 5; done"]
EOF
kubectl apply -f broken-backend.yaml
```

Wait about 15 seconds for the new Pod to start, then check the logs:

```bash
kubectl logs -l app=backend --tail=10
```

**Your Task:**

- What does the Backend log say now? Is the DB reachable or unreachable?
- Inside the Pod, the `nc` command is failing. What cluster component is failing to resolve the name `redis-database`?
- If this were a real production app written in Python or Node.js, what specific error type would the application likely throw when trying to connect to a non-existent database DNS name?

(Answer: 1. "Backend: DB unreachable". 2. CoreDNS. It cannot find a Service named `redis-database`, so it returns NXDOMAIN. 3. An ENOTFOUND (Node.js) or socket.gaierror (Python) DNS resolution error).

### Step 6: Cleanup

```bash
kubectl delete -f frontend-tier.yaml
kubectl delete -f backend-tier.yaml
kubectl delete -f db-tier.yaml
kubectl delete -f broken-backend.yaml
```

## Commands

```bash
# Tails the logs of all pods matching the backend label
kubectl logs -l app=backend --tail=5

# Opens a shell inside the deployment's pod
kubectl exec -it deploy/<name> -- sh

# Netcat command to test TCP connectivity
nc -z -w2 <host> <port>

# Check Service endpoints
kubectl get endpoints <svc-name>

# Test DNS resolution
nslookup <service-name>
```

## YAML Explanation

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: db-secret
type: Opaque
stringData:
  redis-password: "supersecret123"
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: redis-db
spec:
  replicas: 1
  selector:
    matchLabels:
      app: db
  template:
    metadata:
      labels:
        app: db
    spec:
      containers:
      - name: redis
        image: redis:alpine
        env:
        - name: REDIS_PASSWORD
          valueFrom:
            secretKeyRef:
              name: db-secret
              key: redis-password
```

### Field-by-Field Explanation

- `Secret.stringData`: Stores the DB password in plain text (Kubernetes base64-encodes it automatically).
- `Deployment.spec.template.spec.containers[0].env`: Injects the Secret as an environment variable.
- `secretKeyRef.name`: References the Secret name.
- `secretKeyRef.key`: References the key within the Secret.

## Production Notes

- **Use ConfigMaps for Endpoints:** Inject the Backend Service name into the Frontend via a ConfigMap. Don't hardcode it in the Docker image.
- **Use Secrets for DB Passwords:** Never bake credentials into Docker images.
- **Don't expose DBs externally:** The Database Service should strictly be `type: ClusterIP`. Never use a LoadBalancer or NodePort for a database in production.
- **Use StatefulSets for DBs:** Deployments are for stateless apps. Use StatefulSets for databases to ensure stable network identities and persistent storage.

### When to Use / When NOT to Use

**Use a 3-Tier Architecture when:**

- Standard web applications with a clear UI, API, and data boundary.
- When teams specialize (Frontend team works on UI, Backend team works on API).

**Avoid 3-Tier Architecture when:**

- If your app is a simple static site (just Frontend).
- If your app is a massive monolith where the UI and API are inextricably linked.

### Performance and Security Considerations

**Performance:** Cross-tier network calls add latency. Ensure Services are in the same cluster/region to minimize round-trip time.

**Security:** Restrict traffic using Network Policies. The Frontend should only talk to the Backend. The Backend should only talk to the Database. Block all other traffic.

## Best Practices

- Use Services for stable DNS names.
- Use Secrets for credentials.
- Use ConfigMaps for configuration.
- Don't expose databases externally.
- Use Network Policies to restrict traffic.
- Use StatefulSets for databases.

## Common Mistakes

| Mistake | Why It Happens | How to Avoid It |
|---------|----------------|-----------------|
| Hardcoding Namespaces | Using `db-svc.prod` in config | Use short names (`db-svc`) so CoreDNS resolves within the same namespace |
| Typo in Service Name | `backend-api` vs `backend-svc` | Double-check Service names and use `nslookup` to verify |
| Exposing DBs via NodePort | Accidental LoadBalancer/NodePort | Always use `type: ClusterIP` for databases |
| Not using Secrets | Baking passwords into images | Always use Secrets for credentials |

## Troubleshooting

**Symptom: Frontend cannot reach Backend**

Cause: DNS resolution failure or Service mismatch.

```bash
kubectl get endpoints backend-api
kubectl exec -it <pod> -- nslookup backend-api
```

Fix: Ensure the Service selector matches the Backend Pod labels.

**Symptom: Backend cannot reach Database**

Cause: DNS resolution failure or Secret not injected.

```bash
kubectl get endpoints redis-db
kubectl exec -it <pod> -- env | grep REDIS
```

Fix: Ensure the Secret exists and is correctly referenced.

**Symptom: `NXDOMAIN` error**

Cause: Typo in Service name.

```bash
kubectl get svc | grep <partial-name>
```

Fix: Check the Service name and update the configuration.

## Interview Questions

**Q: How do you wire a frontend, backend, and database together in Kubernetes?**

A: Each tier is a separate Deployment with its own ClusterIP Service. The Frontend talks to the Backend Service by name, and the Backend talks to the Database Service by name. CoreDNS handles the name resolution. Secrets are used to pass database credentials to the Backend.

**Q: If an app throws an ENOTFOUND or NXDOMAIN error, what Kubernetes component failed?**

A: CoreDNS. The app asked for a Service name that doesn't exist in the cluster, likely due to a typo in the ConfigMap or environment variable.

**Q: You deploy a 3-tier app. The frontend works, but the backend cannot connect to the database. The database is running. What are the first three things you check?**

A:
1. Does the backend config point to the correct DB Service DNS name?
2. Does the DB Service have Endpoints? (`kubectl get endpoints db-svc`). If empty, the Service selector doesn't match the DB Pod labels.
3. Is there a Network Policy blocking traffic between the backend namespace and the database namespace?

**Q: You should expose your database using a LoadBalancer Service. True or False?**

A: False. Use ClusterIP.

**Q: The Frontend can talk to the Backend using the Backend Pod's IP directly. True or False?**

A: False. Pod IPs are ephemeral. Use the Service DNS name.

## Scenario Questions

**Scenario 1:** Your backend cannot connect to the database. The database is running. How do you diagnose?

A: I would check `kubectl get endpoints redis-db` to see if the Service has matching Pods. I would check DNS resolution with `nslookup redis-db`. I would check if the Secret is correctly injected.

**Scenario 2:** You need to connect a backend in namespace `app-tier` to a database in namespace `data-tier`. How do you do this?

A: I would use the FQDN: `redis-db.data-tier.svc.cluster.local`. CoreDNS can resolve Services across namespaces.

**Scenario 3 (Mini Project - The Cross-Namespace App):**

Create a namespace called `data-tier`. Deploy the Redis database in the `data-tier` namespace. Create a namespace called `app-tier`. Deploy the Backend in the `app-tier` namespace. Modify its command to connect to `redis-db.data-tier.svc.cluster.local` (using the FQDN). Verify the backend can reach the database across namespaces.

## Quiz

1. What is the default Service type for internal communication?
   - A. LoadBalancer
   - B. NodePort
   - C. ClusterIP
   - D. ExternalName

2. What component resolves Service names to ClusterIPs?
   - A. kube-proxy
   - B. CoreDNS
   - C. API Server
   - D. etcd

3. What error does CoreDNS return for a non-existent Service?
   - A. 404 Not Found
   - B. NXDOMAIN
   - C. Connection Refused
   - D. Timeout

4. How should database credentials be passed to a Backend Pod?
   - A. Hardcoded in Docker image
   - B. Environment variable from a Secret
   - C. ConfigMap
   - D. Command-line argument

5. Which namespace-scoped resource should be used for a database?
   - A. Deployment
   - B. StatefulSet
   - C. DaemonSet
   - D. Job

Answers: 1-C, 2-B, 3-B, 4-B, 5-B.

## Revision

One-minute revision:

- 3-Tiers = UI, API, DB.
- Connect via DNS (`svc-name`).
- DB creds via Secrets.
- NXDOMAIN = Typo in service name.

Memory trick:

- **Frontend:** The Waiter.
- **Backend:** The Chef.
- **Database:** The Pantry.
- **CoreDNS:** The restaurant's internal phone directory.

Key facts:

- 3-Tier = Separation of concerns.
- Services = Stable DNS.
- Secrets = Credentials.
- CoreDNS = Name resolution.
- NXDOMAIN = DNS failure.

## Cheat Sheet

| Command | What it does |
|---------|--------------|
| `kubectl logs -l app=backend --tail=5` | Tails the logs of all pods matching the backend label |
| `kubectl exec -it deploy/<name> -- sh` | Opens a shell inside the deployment's pod |
| `nc -z -w2 <host> <port>` | Netcat command to test TCP connectivity |

## References

- [Kubernetes Documentation: Connecting Applications](https://kubernetes.io/docs/tutorials/connecting-apps/)
- [Kubernetes Documentation: Services](https://kubernetes.io/docs/concepts/services-networking/service/)
- [Kubernetes Documentation: DNS](https://kubernetes.io/docs/concepts/services-networking/dns-pod-service/)
- [CoreDNS Documentation](https://coredns.io/)

## Related Lessons

- [Lesson 9 - Services and Cluster Networking](../04-networking/lesson-14-services-and-cluster-networking.md) - how Services work.
- [Lesson 19 - ConfigMaps and Secrets](../06-configuration/lesson-20-configmaps-and-secrets.md) - injecting configuration.
- [Lesson 13 - Network Policies](../04-networking/lesson-16-network-policies.md) - network isolation.

## Coming Next

Now that you understand how to build a 3-tier application, the next lesson covers Autoscaling — how to automatically scale your applications based on traffic.
