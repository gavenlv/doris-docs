# Quick Start - Using Your Nexus Credentials

## Nexus Credentials

- **Username**: admin
- **Password**: adminadmin
- **Web UI**: http://localhost:8081
- **Docker Registry**: localhost:8082

---

## Option 1: One-Click Verification (Recommended)

### Windows

```powershell
# Double-click in project root directory
.\verify.bat
```

### Linux/macOS

```bash
# Grant execute permissions
chmod +x scripts/*.sh

# Run verification
./scripts/local-verify.sh all
```

---

## Option 2: Step-by-Step Manual Verification

### Step 1: Ensure Nexus is Running

```bash
# Check Nexus status
docker ps | grep doris-nexus

# If not running, start it
docker run -d --name doris-nexus -p 8081:8081 -p 8082:8082 sonatype/nexus3:latest

# Wait 2 minutes for startup
echo "Waiting for Nexus to start..."
sleep 120
```

### Step 2: Login to Nexus Web UI

1. Open browser and visit: http://localhost:8081
2. Click **Sign in** in the top right corner
3. Enter:
   - Username: `admin`
   - Password: `adminadmin`
4. Click Login

### Step 3: Create Docker Repository

1. After login, click the gear icon (Settings)
2. Select **Repositories** → **Create repository**
3. Choose **docker (hosted)**
4. Fill in:
   - Name: `doris-docker`
   - HTTP Port: `8082`
   - Keep other defaults
5. Click **Create repository**

### Step 4: Prepare Offline Package

Doris 3.x uses a unified binary package format (no longer separate FE/BE packages).

```powershell
# Windows PowerShell - Create directory
mkdir offline-packages

# Download Doris 3.0.5 (unified binary package)
# Source: Alibaba Cloud OSS (official mirror)
Invoke-WebRequest -Uri "https://apache-doris-releases.oss-accelerate.aliyuncs.com/apache-doris-3.0.5-bin-x64.tar.gz" -OutFile "offline-packages\apache-doris-3.0.5-bin-x64.tar.gz"
```

**Note**: Doris 3.1.4 only has source packages on Apache archives. Version 3.0.5 is the recommended stable version with binary packages available.

### Step 5: Build Images

```powershell
# Build FE (extracts from unified package)
cd docker\fe
docker build --build-arg DORIS_VERSION=3.0.5 --build-arg OFFLINE_PATH=C:\workspace\github\doris-docs\doris-gke-cluster-build-from-ubuntu-latest\offline-packages -t doris-fe:3.0.5 ..

# Build BE (extracts from unified package)
cd ..\be
docker build --build-arg DORIS_VERSION=3.0.5 --build-arg OFFLINE_PATH=C:\workspace\github\doris-docs\doris-gke-cluster-build-from-ubuntu-latest\offline-packages -t doris-be:3.0.5 ..
```

### Step 6: Push to Nexus

```powershell
# Login to Nexus Docker Registry
docker login localhost:8082 -u admin -p adminadmin

# Tag images
docker tag doris-fe:3.0.5 localhost:8082/doris/fe:3.0.5-secure
docker tag doris-be:3.0.5 localhost:8082/doris/be:3.0.5-secure

# Push
docker push localhost:8082/doris/fe:3.0.5-secure
docker push localhost:8082/doris/be:3.0.5-secure
```

### Step 7: Verify Pull

```powershell
# Delete local images
docker rmi localhost:8082/doris/fe:3.0.5-secure
docker rmi localhost:8082/doris/be:3.0.5-secure

# Pull from Nexus
docker pull localhost:8082/doris/fe:3.0.5-secure
docker pull localhost:8082/doris/be:3.0.5-secure

# View images
docker images | findstr "doris"
```

---

## Troubleshooting

### Issue: Nexus Login Failed

**Check**:
1. Is Nexus running: `docker ps | grep nexus`
2. Using correct password: `adminadmin`
3. Wait for full startup: First startup takes 2 minutes

**Solution**:
```bash
# View Nexus logs
docker logs doris-nexus --tail 50

# Reset password
docker exec -it doris-nexus /bin/bash
cd /opt/sonatype/nexus/bin
./nexus reset-admin-password
```

### Issue: Docker Push Failed

**Check**:
1. Are you logged in: `docker login localhost:8082`
2. Is repository created: Check in Nexus Web UI

**Solution**:
```bash
# Re-login
docker logout localhost:8082
docker login localhost:8082 -u admin -p adminadmin
```

### Issue: Download Failed (404 Not Found)

**Reason**: Doris 3.1.4 only has source packages, no binary packages on Apache archives.

**Solution**: Use version 3.0.5 with Alibaba Cloud OSS download link:
```powershell
Invoke-WebRequest -Uri "https://apache-doris-releases.oss-accelerate.aliyuncs.com/apache-doris-3.0.5-bin-x64.tar.gz" -OutFile "offline-packages\apache-doris-3.0.5-bin-x64.tar.gz"
```

---

## Verification Success Criteria

✅ Can access http://localhost:8081 and login  
✅ Created `doris-docker` repository  
✅ Successfully built `doris-fe:3.0.5` and `doris-be:3.0.5`  
✅ Successfully pushed to `localhost:8082/doris/fe:3.0.5-secure`  
✅ Can pull images from Nexus  

---

## Next Steps

After successful verification, you can:
1. Run security scan: `./scripts/scan-images.sh all`
2. Deploy to GKE: `./scripts/deploy.sh`
3. View full documentation: `docs/DEPLOYMENT-GUIDE.md`
