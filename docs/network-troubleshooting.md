# Network Troubleshooting Guide

## Quick Diagnostics

### 1. Service Connectivity Issues

```bash
# Check basic connectivity
ping <service_ip>
traceroute <service_ip>

# Verify DNS resolution
nslookup <service_name>.local
dig <service_name>.example.com

# Test specific service ports
nc -zv <service_ip> <port>
telnet <service_ip> <port>
```

### 2. VLAN Connectivity

```bash
# Check VLAN interfaces
ip link show
ip addr show

# Verify VLAN routing
ip route show table all
bridge vlan show

# Test inter-VLAN communication
ping -I <vlan_interface> <target_ip>
```

### 3. Docker Network Issues

```bash
# List networks
docker network ls
docker network inspect <network_name>

# Check container connectivity
docker exec <container> ping <target>
docker logs <container>
```

## Common Issues and Solutions

### 1. External Access Problems

| Issue | Symptoms | Diagnostic Steps | Solution |
|-------|----------|-----------------|-----------|
| Traefik Unreachable | - 502 Bad Gateway<br>- Connection timeout | 1. Check Traefik logs<br>2. Verify port bindings<br>3. Check SSL certificates | - Restart Traefik<br>- Renew certificates<br>- Verify firewall rules |
| VPN Connection Failed | - Connection timeout<br>- Authentication errors | 1. Check WireGuard logs<br>2. Verify peer configurations<br>3. Test UDP port 51820 | - Update WireGuard config<br>- Check firewall rules<br>- Verify peer keys |
| DNS Resolution Failed | - Name resolution errors<br>- Incorrect IP resolution | 1. Check DNS server<br>2. Verify DNS records<br>3. Test local resolution | - Update DNS records<br>- Clear DNS cache<br>- Check DNS server status |

### 2. Internal Network Issues

| Issue | Symptoms | Diagnostic Steps | Solution |
|-------|----------|-----------------|-----------|
| Inter-VLAN Routing | - Services unreachable<br>- Partial connectivity | 1. Check VLAN configs<br>2. Verify routing tables<br>3. Test VLAN interfaces | - Update VLAN config<br>- Fix routing rules<br>- Restart network services |
| Docker Network | - Container isolation<br>- Network conflicts | 1. Inspect networks<br>2. Check container logs<br>3. Verify network drivers | - Recreate networks<br>- Update container configs<br>- Fix IP conflicts |
| Service Discovery | - Services can't find each other<br>- DNS resolution fails | 1. Check Docker DNS<br>2. Verify service names<br>3. Test internal DNS | - Update service names<br>- Fix DNS configuration<br>- Restart Docker daemon |

### 3. Storage Access Problems

| Issue | Symptoms | Diagnostic Steps | Solution |
|-------|----------|-----------------|-----------|
| NFS Mount Failed | - Mount timeout<br>- IO errors | 1. Check NFS service<br>2. Verify mount points<br>3. Test NFS ports | - Restart NFS service<br>- Update mount options<br>- Check permissions |
| SMB Access | - Connection refused<br>- Authentication failed | 1. Check SMB service<br>2. Verify credentials<br>3. Test SMB ports | - Update credentials<br>- Fix permissions<br>- Restart SMB service |
| Backup Storage | - Backup failures<br>- Space issues | 1. Check storage space<br>2. Verify permissions<br>3. Test backup paths | - Clean old backups<br>- Fix permissions<br>- Update backup config |

## Diagnostic Commands

### Network Status

```bash
# Interface Status
ip -s link show
ethtool <interface>

# Routing Table
ip route show
ip rule show

# Connection Status
ss -tuln
netstat -tupln
```

### Docker Networks

```bash
# Network Details
docker network inspect <network>

# Container Networking
docker exec <container> ip addr
docker exec <container> netstat -tupln

# Network Logs
docker events --filter type=network
```

### Service Health

```bash
# Service Status
docker-compose ps
docker service ls

# Container Logs
docker-compose logs <service>
docker service logs <service>

# Health Checks
curl -v http://localhost:<port>/health
wget -O- http://localhost:<port>/metrics
```

## Recovery Procedures

### 1. Network Recovery

```bash
# 1. Stop affected services
docker-compose stop <service>

# 2. Reset network state
ip link set <interface> down
ip link set <interface> up

# 3. Recreate Docker networks
docker-compose down
docker network prune
docker-compose up -d

# 4. Verify connectivity
ping -c 4 <service_ip>
curl -v http://<service>:<port>/health
```

### 2. VLAN Recovery

```bash
# 1. Check VLAN status
ip link show type vlan

# 2. Recreate VLAN interface
ip link delete <vlan_interface>
ip link add link <parent> name <vlan_interface> type vlan id <vlan_id>
ip link set <vlan_interface> up

# 3. Update routing
ip route add <subnet> dev <vlan_interface>

# 4. Verify connectivity
ping -I <vlan_interface> <target_ip>
```

### 3. Service Recovery

```bash
# 1. Backup configurations
cp -r /path/to/config /path/to/backup

# 2. Reset service
docker-compose rm -f <service>
docker volume rm <service_volume>

# 3. Restore configuration
cp -r /path/to/backup /path/to/config

# 4. Restart service
docker-compose up -d <service>
```

## Monitoring and Prevention

### 1. Network Monitoring

```yaml
# Prometheus Alert Rules
groups:
- name: network_alerts
  rules:
  - alert: NetworkLatencyHigh
    expr: network_latency_seconds > 0.1
    for: 5m
    labels:
      severity: warning
    annotations:
      description: "Network latency is high"

  - alert: VLANConnectivityLost
    expr: vlan_status == 0
    for: 1m
    labels:
      severity: critical
    annotations:
      description: "VLAN connectivity lost"
```

### 2. Service Monitoring

```yaml
# Docker Health Checks
healthcheck:
  test: ["CMD", "curl", "-f", "http://localhost:8080/health"]
  interval: 30s
  timeout: 10s
  retries: 3
  start_period: 40s
```

### 3. Automated Recovery

```powershell
# PowerShell Recovery Script
function Test-ServiceHealth {
    param($Service)
    try {
        $response = Invoke-WebRequest "http://$Service:8080/health"
        return $response.StatusCode -eq 200
    } catch {
        return $false
    }
}

function Restore-Service {
    param($Service)
    Write-Host "Recovering $Service..."
    docker-compose restart $Service
    Start-Sleep -Seconds 30
    if (Test-ServiceHealth $Service) {
        Write-Host "$Service recovered successfully"
    } else {
        Write-Host "$Service recovery failed"
    }
}
```

## Preventive Maintenance

1. **Regular Health Checks**
   - Run network diagnostics daily
   - Monitor service health metrics
   - Check backup integrity

2. **Configuration Backups**
   - Backup network configurations
   - Store VLAN settings
   - Archive service configurations

3. **Documentation Updates**
   - Record all network changes
   - Update troubleshooting procedures
   - Document recovery steps