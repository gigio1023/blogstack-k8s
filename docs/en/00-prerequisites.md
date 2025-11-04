# 00. Prerequisites

Requirements and setup instructions before deploying blogstack-k8s.

---

## 1. Infrastructure

### Oracle Cloud Infrastructure (OCI) VM

Required specifications:
- VM Shape: VM.Standard.A1.Flex (ARM64)
- OCPU: 4 (recommended)
- Memory: 24GB (recommended)
- Storage: Minimum 100GB Boot Volume
- OS: Ubuntu 22.04 LTS (ARM64)

### Network Configuration

VCN Security List settings:

| Direction | CIDR | Protocol/Port | Description |
|-----------|------|---------------|-------------|
| Egress | 0.0.0.0/0 | TCP/443 | Required: GitHub, Docker Hub, Helm |
| Egress | 0.0.0.0/0 | TCP/80 | Optional: Package updates |
| Ingress | - | - | Not required (Cloudflare Tunnel) |

Note: Close all ingress rules except SSH (22). Blog access is through Cloudflare Tunnel only.

### VM Creation Verification

```bash
# SSH connection test
ssh -i ~/.ssh/oci_key ubuntu@<VM_PUBLIC_IP>

# System info
uname -m  # Expected: aarch64 (ARM64)
cat /etc/os-release  # Ubuntu version
df -h  # Disk space (minimum 50GB free)
```

---

## 2. Cloudflare Account Setup

### 2.1. Cloudflare Account and Domain

#### Step 1: Cloudflare Sign-up
1. Create account at https://dash.cloudflare.com/sign-up
2. Verify email

#### Step 2: Domain Purchase and Configuration

**Method A: Cloudflare Registrar (Recommended)**

Purchase domain directly from Cloudflare:

1. Cloudflare Dashboard: **Domain Registration** → **Register Domains**
2. Search and purchase domain
3. DNS automatically configured (no nameserver change needed)

Benefits:
- Automatic nameserver setup
- Lower renewal costs (at-cost pricing)
- Full Cloudflare integration

**Method B: Existing Domain (Other Registrar)**

Add domain purchased from GoDaddy, Namecheap, etc.:

1. Cloudflare Dashboard: **Add a Site**
2. Enter domain: `yourdomain.com`
3. Select plan: **Free**
4. Scan DNS records → **Continue**
5. Change nameservers at your registrar to Cloudflare's nameservers:

```
nameserver1: chad.ns.cloudflare.com
nameserver2: dina.ns.cloudflare.com
```

Nameserver change by registrar:
- GoDaddy: DNS Management → Nameservers → Change
- Namecheap: Domain List → Manage → Custom DNS
- Other: Search for "Custom Nameservers" in DNS settings

Verify nameserver change (propagation may take up to 24 hours):
```bash
dig NS yourdomain.com +short

# Expected output:
# chad.ns.cloudflare.com
# dina.ns.cloudflare.com
```

---

### 2.2. Cloudflare Zero Trust Activation

#### Step 1: Access Zero Trust Dashboard
1. Navigate to https://one.dash.cloudflare.com/
2. Login with Cloudflare account

#### Step 2: Create Team Domain
- Enter team name: `myblog-team` (any name)
- Select plan: **Free** (up to 50 users)
- Click **Continue to dashboard**

---

### 2.3. Cloudflare Tunnel Creation

#### Step 1: Navigate to Tunnels
1. Zero Trust Dashboard: https://one.dash.cloudflare.com/
2. Left menu: **Networks** → **Tunnels**
3. Click **Create a tunnel**

#### Step 2: Select Tunnel Type
- Select **Cloudflared** (recommended)
- Click **Next**

#### Step 3: Enter Tunnel Name
- Name: `blogstack-tunnel`
- Click **Save tunnel**

#### Step 4: Copy Token
Copy and securely store the displayed token.

Token format: Long Base64-encoded string (approximately 200+ characters)

Skip connector installation step (cloudflared Pod runs automatically in Kubernetes)

#### Step 5: Public Hostname Configuration (Later)
This step will be performed after Vault secret injection in 03-vault-setup.md

---

### 2.4. Zero Trust Access Policy (Optional)

To protect Ghost Admin page (`/ghost/*`):

#### Step 1: IdP Integration (Google/GitHub)
1. Settings → Authentication → Login methods
2. Click Add new
3. Select Google or GitHub
4. Create and integrate OAuth app

#### Step 2: Create Application
1. Access → Applications → Add an application
2. Application type: Self-hosted
3. Application name: `Ghost Admin`
4. Application domain: `yourdomain.com`
5. Path: `/ghost/*`
6. Click Next

#### Step 3: Configure Policy
| Setting | Value |
|---------|-------|
| Policy name | `Admin Only` |
| Action | `Allow` |
| Session duration | `24 hours` |
| Include | Emails: `your-email@gmail.com` |

Click Add application

Note: This configuration requires Google/GitHub login when accessing `/ghost/*`

---

## 3. Development Tools (Inside VM)

### Required Tools on VM

```bash
# SSH into VM
ssh -i ~/.ssh/oci_key ubuntu@<VM_PUBLIC_IP>

# Install basic tools
sudo apt update
sudo apt install -y curl git jq

# Verify Git version
git --version  # 2.30+ required

# kubectl is automatically provided by k3s installation
```

### Local Development Tools (Optional)

To manage cluster from local machine:

```bash
# macOS
brew install kubectl kustomize

# Linux
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

# Verify versions
kubectl version --client  # 1.28+
kustomize version  # 5.0+
```

---

## 4. Credential Collection

Prepare the following information before deployment:

| Item | Content | Note |
|------|---------|------|
| Cloudflare | Tunnel Token | Base64 string (approx. 200 chars) |
| MySQL | Root Password | Self-generated (8+ chars) |
| | Ghost Password | Self-generated (8+ chars) |
| Ghost | URL | `https://yourdomain.com` |

Tip: Store this information in a secure password manager (1Password, Bitwarden, etc.)

---

## 5. Network Requirements Verification

### External Access Test from VM

```bash
# GitHub access test
curl -I https://github.com

# Docker Hub access test
curl -I https://registry.hub.docker.com

# Cloudflare API access test
curl -I https://api.cloudflare.com

# Expected output: HTTP/2 200 or 3xx
```

### OCI Security List Verification

```bash
# If OCI CLI installed
oci network security-list list --compartment-id <COMPARTMENT_ID>

# Or via OCI Console:
# Networking → Virtual Cloud Networks → [VCN Name] → Security Lists
```

Egress Rules must include:
- Destination: `0.0.0.0/0`, Protocol: `TCP`, Port: `443`

---

## 6. Final Checklist

Pre-deployment checklist:

### Infrastructure
- [ ] OCI VM created (ARM64, Ubuntu 22.04, 4 OCPU, 24GB RAM, 100GB disk)
- [ ] SSH access available (`ssh -i ~/.ssh/oci_key ubuntu@<VM_IP>`)
- [ ] VM outbound 443/tcp allowed (Security List)

### External Services
- [ ] Domain ready (Cloudflare Registrar recommended)
- [ ] Cloudflare account created
- [ ] Domain configured with Cloudflare DNS (verify with `dig NS yourdomain.com`)
- [ ] Cloudflare Zero Trust account activated
- [ ] Cloudflare Tunnel created and token copied

### Credentials
- [ ] Generated 2 MySQL passwords (Root, Ghost)
- [ ] All credentials stored securely

### Tools
- [ ] Git installed on VM
- [ ] (Optional) kubectl, kustomize installed locally

---

## Next Steps

Once all checklist items are complete:

→ [CUSTOMIZATION.md](./CUSTOMIZATION.md) - Configure Git URL and domain (5 min)

→ [01-infrastructure.md](./01-infrastructure.md) - Install k3s (5 min)

---

## Optional Features

Configure additional features beyond basic blog functionality:

### A. Backup (OCI Object Storage)

To enable automatic backup of MySQL database and Ghost content:

#### A.1. Access OCI Console
1. Login to https://cloud.oracle.com/
2. Left menu: Storage → Buckets
3. Click Create Bucket

#### A.2. Bucket Information

| Item | Value | Description |
|------|-------|-------------|
| Bucket Name | `blog-backups` | Any name |
| Default Storage Tier | Standard | Fast access |
| Encryption | Oracle Managed Keys | Default |

Click Create

#### A.3. Generate S3-Compatible API Access Key
1. OCI Console top-right: Profile icon → User Settings
2. Left menu: Customer Secret Keys
3. Click Generate Secret Key
4. Enter name: `blogstack-s3-key`
5. Generate Secret Key → Copy immediately (cannot be viewed again)

Generated credentials:
```bash
Access Key: (32-character alphanumeric string)
Secret Key: (40-character alphanumeric string)
```

#### A.4. Verify Endpoint URL

S3 API Endpoint URL format:
```
https://<namespace>.compat.objectstorage.<region>.oraclecloud.com
```

Verify namespace:
```bash
# If OCI CLI installed
oci os ns get

# Or via OCI Console:
# Bucket details → "Namespace" field
```

Example:
- Namespace: `your-namespace`
- Region: `ap-seoul-1`
- Endpoint: `https://your-namespace.compat.objectstorage.ap-seoul-1.oraclecloud.com`

#### A.5. Enable Backup

See `apps/ghost/optional/README.md` for details

---

### B. Email Sending (SMTP)

To enable Ghost email features (password reset, new post notifications, etc.):

#### B.1. Mailgun (Recommended)

**Step 1: Mailgun Sign-up**
1. Navigate to https://signup.mailgun.com/
2. Click Sign up for free
3. Complete registration and email verification

**Step 2: Add Sending Domain**
1. Mailgun Dashboard: Sending → Domains
2. Click Add New Domain
3. Enter domain name: `mg.yourdomain.com` (subdomain recommended)
4. Click Add Domain

**Step 3: Add DNS Records (in Cloudflare)**
Add DNS records provided by Mailgun to Cloudflare:

| Type | Name | Value | Proxy |
|------|------|-------|-------|
| TXT | `mg` | `v=spf1 include:mailgun.org ~all` | DNS only |
| TXT | `k1._domainkey.mg` | `k=rsa; p=MIGfMA0...` (from Mailgun) | DNS only |
| CNAME | `email.mg` | `mailgun.org` | DNS only |
| MX | `mg` | `mxa.mailgun.org` (Priority: 10) | DNS only |
| MX | `mg` | `mxb.mailgun.org` (Priority: 10) | DNS only |

**Step 4: Verify SMTP Credentials**
1. Mailgun Dashboard: Sending → Domain settings → Select `mg.yourdomain.com`
2. Check SMTP credentials section:

```bash
SMTP Host: smtp.mailgun.org
SMTP Port: 587
Username: postmaster@mg.yourdomain.com
Password: (password generated by Mailgun)
```

**Step 5: Add SMTP to Ghost Secret**

Add SMTP fields to Ghost secret in 03-vault-setup.md:
```bash
vault kv put kv/blog/prod/ghost \
  url="https://yourdomain.com" \
  database__client="mysql" \
  database__connection__host="mysql.blog.svc.cluster.local" \
  database__connection__user="ghost" \
  database__connection__password="YOUR_DB_PASSWORD" \
  database__connection__database="ghost" \
  mail__transport="SMTP" \
  mail__options__service="Mailgun" \
  mail__options__host="smtp.mailgun.org" \
  mail__options__port="587" \
  mail__options__auth__user="postmaster@mg.yourdomain.com" \
  mail__options__auth__pass="YOUR_SMTP_PASSWORD"
```

#### B.2. SendGrid (Alternative)

1. Sign up at https://signup.sendgrid.com/
2. Configure Sender Authentication
3. Generate API Key
4. SMTP credentials:
   - Host: `smtp.sendgrid.net`
   - Port: `587`
   - Username: `apikey`
   - Password: (generated API Key)

#### B.3. Gmail (Test Only)

Note: Gmail has daily sending limits (500 emails), unsuitable for production

1. Enable 2-factor authentication on Gmail account
2. Generate app password: https://myaccount.google.com/apppasswords
3. SMTP credentials:
   - Host: `smtp.gmail.com`
   - Port: `587`
   - Username: `your-email@gmail.com`
   - Password: (16-digit app password)

---

Note: Without SMTP configuration, Ghost email features will not work, but blog publishing and management will function normally.

