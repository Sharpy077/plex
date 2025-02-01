# Network Routing Rules

## Inter-VLAN Routing Policy

### Default Policy
- Default stance: DENY
- All inter-VLAN communication must be explicitly allowed
- Logging enabled for all denied inter-VLAN attempts

### Allowed Routes

#### VLAN 10 → VLAN 20
- Allow HTTP/HTTPS (80/443) to Traefik endpoints
- Allow DNS queries (53) to container DNS
- Allow monitoring traffic (9090-9095) for metrics
- Allow authenticated API calls
- Block all other traffic

#### VLAN 20 → VLAN 10
- Allow DNS queries (53) to primary DNS
- Allow NTP (123) for time sync
- Allow monitoring responses
- Block all other traffic

### Service-Specific Rules

#### Traefik (VLAN 20)
- Accept inbound: 80, 443 from VLAN 10
- Accept inbound: 8080 from monitoring subnet
- Drop all other inbound

#### Monitoring Services (VLAN 20)
- Accept inbound: 9090-9095 from VLAN 10
- Accept outbound: DNS, NTP to VLAN 10
- Drop unauthorized ports

#### Container Services (VLAN 20)
- Must use Traefik as reverse proxy
- No direct external exposure
- Inter-container communication via overlay network only

### Security Rules

#### Rate Limiting
- HTTP/HTTPS: 100 req/sec per IP
- API calls: 50 req/sec per IP
- DNS queries: 10 req/sec per IP

#### Connection Tracking
- TCP session timeout: 3600s
- UDP session timeout: 30s
- ICMP timeout: 30s

#### Security Policies
- Enable SYN flood protection
- Enable TCP MSS clamping
- Drop invalid packets
- Log suspicious activities

### Monitoring Requirements

#### Traffic Monitoring
- Log all inter-VLAN denials
- Monitor bandwidth usage per VLAN
- Track connection states
- Alert on policy violations

#### Health Checks
- Monitor gateway availability
- Track routing table changes
- Verify VLAN tagging
- Monitor ACL effectiveness

### Implementation

#### Firewall Rules (PowerShell)
```powershell
# Allow Traefik access from VLAN 10
New-NetFirewallRule -Name "Allow-VLAN10-Traefik" -DisplayName "Allow VLAN 10 to Traefik" `
    -Direction Inbound -LocalAddress 10.10.20.0/24 -RemoteAddress 10.10.10.0/24 `
    -Protocol TCP -LocalPort 80,443 -Action Allow

# Allow DNS from containers to VLAN 10
New-NetFirewallRule -Name "Allow-Container-DNS" -DisplayName "Allow Container DNS Queries" `
    -Direction Outbound -LocalAddress 10.10.20.0/24 -RemoteAddress 10.10.10.0/24 `
    -Protocol UDP -RemotePort 53 -Action Allow

# Block unauthorized inter-VLAN traffic
New-NetFirewallRule -Name "Block-InterVLAN" -DisplayName "Block Unauthorized Inter-VLAN" `
    -Direction Inbound -LocalAddress 10.10.20.0/24 -RemoteAddress 10.10.10.0/24 `
    -Protocol Any -Action Block
```

#### Docker Network Policy
```yaml
networks:
  proxy:
    driver: bridge
    driver_opts:
      com.docker.network.bridge.name: docker_proxy
      com.docker.network.bridge.enable_icc: "true"
      com.docker.network.bridge.enable_ip_masquerade: "true"
    ipam:
      config:
        - subnet: 10.10.20.0/24
          gateway: 10.10.20.1
    labels:
      - "vlan=20"
      - "security=high"
```