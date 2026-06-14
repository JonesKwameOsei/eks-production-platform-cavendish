# Runbook — Phase 0 Day 2: cert-manager + Let's Encrypt HTTPS

## Goal

Automate TLS certificate provisioning via the ACME HTTP-01 challenge. By end
of day, `curl -I https://api.cavendish.chickenkiller.com` returns HTTP 200
with a valid Let's Encrypt certificate — no browser warnings.

---

## What We're Building

```plaintext
Let's Encrypt CA
       │
       │ 1. cert-manager requests certificate
       │ 2. Let's Encrypt sends HTTP-01 challenge
       │ 3. cert-manager creates temp Ingress to serve token at /.well-known/acme-challenge/
       │ 4. Let's Encrypt verifies → issues certificate
       │ 5. cert-manager stores cert as Kubernetes Secret
       │ 6. Nginx Ingress Controller picks up TLS secret → serves HTTPS
       ▼
┌─────────────────────────────────────────────┐
│  EC2 (k3s)                                   │
│                                              │
│  cert-manager → ClusterIssuer → Certificate  │
│                                              │
│  Nginx Ingress Controller (port 443 + TLS)   │
└─────────────────────────────────────────────┘
```

---

## Prerequisites (from Day 1)

- ✅ k3s running with Nginx Ingress Controller
- ✅ FreeDNS subdomain resolving to EC2 IP
- ✅ Port 80 open in security group (Let's Encrypt needs this for HTTP-01)
- ✅ `curl http://api.cavendish.chickenkiller.com` returns 200

---

## Step 1: Open Port 443 in EC2 Security Group

Let's Encrypt issues the challenge over port 80, but we need 443 open to
serve HTTPS traffic after the certificate is issued.

1. AWS Console → EC2 → Security Groups → our instance's SG
2. Add inbound rule:
   - **Type**: HTTPS
   - **Port**: 443
   - **Source**: `0.0.0.0/0`
3. Save

> **Verify both ports are open**: Port 80 (for HTTP-01 challenge) and Port 443
> (for HTTPS traffic).

---

## Step 2: Install cert-manager via Helm

```bash
# Add the cert-manager Helm repo
helm repo add jetstack https://charts.jetstack.io
helm repo update

# Install cert-manager with CRDs
helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --set crds.enabled=true
```

**Verify cert-manager is running**:

```bash
kubectl get pods -n cert-manager
```

**Expected output**:

```plaintext
NAME                                       READY   STATUS    RESTARTS   AGE
cert-manager-xxxxxxxxx-xxxxx               1/1     Running   0          108s
cert-manager-cainjector-xxxxxxxxx-xxxxx    1/1     Running   0          108s
cert-manager-webhook-xxxxxxxxx-xxxxx       1/1     Running   0          108s
```

All three pods must be Running before proceeding.

> **Understanding**: cert-manager is a Kubernetes controller that watches for
> Certificate resources and automates the ACME protocol (request → challenge →
> verify → store). On EKS, ACM replaces this entirely — AWS manages
> certificate lifecycle internally.

---

## Step 3: Create a ClusterIssuer

The ClusterIssuer tells cert-manager *where* to get certificates from (Let's
Encrypt) and *how* to prove domain ownership (HTTP-01).

```bash
cat <<EOF | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: my-email@example.com
    privateKeySecretRef:
      name: letsencrypt-prod-key
    solvers:
      - http01:
          ingress:
            class: nginx
EOF
```

> **Replace** `my-email@example.com` with a real email — Let's Encrypt uses
> it for expiry notifications.

**outcome**:

```plaintext
clusterissuer.cert-manager.io/letsencrypt-prod created
```

**Verify the ClusterIssuer is ready**:

```bash
kubectl get clusterissuer letsencrypt-prod
```

**Expected output**:

```plaintext
NAME               READY   AGE
letsencrypt-prod   True    18s
```

If READY is `False`, check:

```bash
kubectl describe clusterissuer letsencrypt-prod
```

> **Understanding**: The ClusterIssuer is cluster-wide (not namespace-scoped).
> `http01` solver means cert-manager will serve a token at
> `/.well-known/acme-challenge/{token}` via a temporary Ingress. Let's Encrypt
> hits that URL over port 80 to verify we control the domain.

---

## Step 4: Update the Ingress with TLS Configuration

We add two things to our existing Ingress:

1. The `cert-manager.io/cluster-issuer` annotation — tells cert-manager to
   issue a cert for this Ingress
2. A `tls` block — specifies which hostname to secure and where to store the
   cert

```bash
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: http-echo-ingress
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
    cert-manager.io/cluster-issuer: letsencrypt-prod
spec:
  ingressClassName: nginx
  tls:
    - hosts:
        - api.cavendish.chickenkiller.com
      secretName: http-echo-tls
  rules:
    - host: api.cavendish.chickenkiller.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: http-echo
                port:
                  number: 80
EOF
```

**outcome**:

```plaintext
ingress.networking.k8s.io/http-echo-ingress configured
```

> **What just happened**: cert-manager detected the `cert-manager.io/cluster-issuer`
> annotation and created a Certificate resource automatically. It then starts
> the ACME HTTP-01 challenge flow.

---

## Step 5: Watch the Challenge Complete

This is the part that matters — we get to see the ACME protocol in action.

```bash
# Watch the challenge in real time
kubectl get challenges --all-namespaces -w
```

**Expected flow**:

```plaintext
NAMESPACE   NAME                              STATE     AGE
default     http-echo-tls-xxxxx-xxxxxxx       pending   5s
default     http-echo-tls-xxxxx-xxxxxxx       valid     30s
```

Once `STATE` shows `valid`, press Ctrl+C.

If the challenge stays `pending` for more than 2 minutes, debug with:

```bash
kubectl describe challenge -l acme.cert-manager.io/order-name
```

**Common failures**:

| Issue | Cause | Fix |
| ------- | ------- | ----- |
| Challenge stays pending | Port 80 not open | Check security group allows HTTP from 0.0.0.0/0 |
| Connection refused | Ingress controller not on port 80 | Verify `sudo ss -tlnp \| grep :80` shows nginx |
| DNS lookup failed | FreeDNS not resolving | Verify `dig api.cavendish.chickenkiller.com +short` returns EC2 IP |
| Unauthorized | Wrong ClusterIssuer name | Check annotation matches ClusterIssuer name exactly |

---

## Step 6: Verify the Certificate

```bash
kubectl get certificate
```

**Expected output**:

```plaintext
NAME             READY   SECRET          AGE
http-echo-tls    True    http-echo-tls   60s
```

`READY: True` means the certificate was issued and stored.

**Inspect the secret**:

```bash
kubectl get secret http-echo-tls
```

**Expected output**:

```plaintext
NAME             TYPE                DATA   AGE
http-echo-tls    kubernetes.io/tls   2      60s
```

The `DATA: 2` means it contains both `tls.crt` (certificate) and `tls.key`
(private key).

> **Understanding**: On EKS with ACM, this secret never exists in the cluster.
> The certificate is attached directly to the ALB — invisible to Kubernetes.
> Phase 0 shows us where the cert actually lives and how it gets there.

---

## Step 7: Test HTTPS

```bash
# From the EC2 instance or our local machine
curl -I https://api.cavendish.chickenkiller.com
```

**Expected output**:

```plaintext
HTTP/2 200
server: nginx
date: ...
content-type: text/plain
strict-transport-security: max-age=15724800; includeSubDomains
```

No certificate warning. Valid HTTPS.

**If curl shows certificate errors**, try with verbose output:

```bash
curl -vI https://api.cavendish.chickenkiller.com 2>&1 | grep -E "subject|issuer|expire"
```

Should show:

- `issuer: CN=Let's Encrypt Authority X3` (or similar)
- A valid expiry date (~90 days from now)

---

## Step 8: Documentation

```bash
echo "=== P0-D2 Verification ===" > ~/phase0-day2-evidence.txt
echo "Timestamp: $(date -u '+%Y-%m-%d %H:%M:%S UTC')" >> ~/phase0-day2-evidence.txt
echo "" >> ~/phase0-day2-evidence.txt
echo "--- kubectl get certificate ---" >> ~/phase0-day2-evidence.txt
kubectl get certificate >> ~/phase0-day2-evidence.txt
echo "" >> ~/phase0-day2-evidence.txt
echo "--- curl -I https ---" >> ~/phase0-day2-evidence.txt
curl -I https://api.cavendish.chickenkiller.com >> ~/phase0-day2-evidence.txt 2>&1
echo "" >> ~/phase0-day2-evidence.txt
echo "--- kubectl get secret ---" >> ~/phase0-day2-evidence.txt
kubectl get secret http-echo-tls >> ~/phase0-day2-evidence.txt
echo "" >> ~/phase0-day2-evidence.txt
echo "--- certificate details ---" >> ~/phase0-day2-evidence.txt
kubectl describe certificate http-echo-tls >> ~/phase0-day2-evidence.txt

cat ~/phase0-day2-evidence.txt
```

---

## Day 2 — Deliverable Checklist (P0-D2)

| # | Check | Command | Expected |
| --- | ------- | --------- | ---------- |
| 1 | cert-manager pods Running | `kubectl get pods -n cert-manager` | 3/3 Running |
| 2 | ClusterIssuer is Ready | `kubectl get clusterissuer` | READY: True |
| 3 | Certificate is Ready | `kubectl get certificate` | READY: True |
| 4 | TLS secret exists | `kubectl get secret http-echo-tls` | TYPE: kubernetes.io/tls |
| 5 | HTTPS returns 200 | `curl -I https://api.cavendish.chickenkiller.com` | HTTP/2 200 |
| 6 | No certificate warning | Browser or `curl` with no `-k` flag | Valid cert, no errors |

** All 6 checks pass = Day 2 complete ✅*

---

## What We Now Understand

After Day 2, we can explain:

1. **What the ACME protocol does** — a standardized challenge-response flow
   to prove domain ownership before a CA issues a certificate
2. **Why port 80 must be open** — Let's Encrypt sends the HTTP-01 challenge
   over port 80 to `/.well-known/acme-challenge/{token}`
3. **Where the certificate is stored** — as a Kubernetes Secret of type
   `kubernetes.io/tls` containing `tls.crt` and `tls.key`
4. **What cert-manager would do in 89 days** — automatically renew the
   certificate before the 90-day expiry (Let's Encrypt certs are short-lived
   by design)
5. **How ACM replaces all of this on EKS** — AWS handles the challenge
   internally, stores the cert outside Kubernetes, attaches it directly to the
   ALB, and renews automatically. Same outcome, invisible mechanism.

## EKS Mapping

| What we did manually | What EKS does instead |
| ----------------------- | ----------------------- |
| Installed cert-manager + ClusterIssuer | ACM provisions cert with one Terraform resource |
| HTTP-01 challenge via temporary Ingress | ACM uses DNS or email validation internally |
| Certificate stored as Kubernetes Secret | Certificate attached to ALB — never in cluster |
| Auto-renewal in 89 days by cert-manager | Auto-renewal managed by AWS — zero config |
| `cert-manager.io/cluster-issuer` annotation | `alb.ingress.kubernetes.io/certificate-arn` annotation |
