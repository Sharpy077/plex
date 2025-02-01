# Network Topology Documentation

## Overview
The network is segmented into multiple VLANs:
- VLAN 10: Primary network for current devices
- VLAN 20: Dedicated Docker container network

## Network Segments

### VLAN 10 (Primary Network)
- Subnet: 10.10.10.0/24
- Gateway: 10.10.10.1
- Purpose: Current devices and primary network traffic
- DHCP Range: 10.10.10.50 - 10.10.10.254
- Reserved Range: 10.10.10.2 - 10.10.10.49 (for static assignments)

### VLAN 20 (Docker Network)
- Subnet: 10.10.20.0/24
- Gateway: 10.10.20.1
- Purpose: Docker container networking only
- DHCP Range: 10.10.20.50 - 10.10.20.254
- Reserved Range: 10.10.20.2 - 10.10.20.49 (for static assignments)

### Container Network Bridge
- Name: docker_proxy
- Driver: bridge
- Network Mode: bridge
- ICC (Inter-Container Communication): enabled
- IP Masquerade: enabled
- VLAN Tagging: Enforced for VLAN 20

### IP Whitelisting
- Internal Networks: 10.10.0.0/16
- External Access: 202.128.124.242/32

## Network Security

### Access Control
- Inter-VLAN Routing:
  - VLAN 10 ↔ VLAN 20: Controlled via firewall rules
  - Default: No direct routing between VLANs
- External Access: Limited to whitelisted IPs
- Container Communication: Restricted to necessary services

### Security Measures
- Network Isolation:
  - VLAN 10: Primary device isolation
  - VLAN 20: Container isolation
- Traffic Filtering:
  - VLAN-aware bridge configuration
  - Inter-VLAN ACLs
- MAC Address Filtering: Enabled on both VLANs
- Port Security: Enforced through Traefik for containers

## Service Discovery
- DNS Resolution:
  - VLAN 10: Primary DNS services
  - VLAN 20: Internal DNS for container names
- Service Mesh: Traefik for container routing
- Health Checks: Implemented at container level

## Network Validation Rules
1. VLAN Configuration
   - Current devices must use VLAN 10
   - Docker containers must use VLAN 20
   - No cross-VLAN container deployment
   - Proper VLAN tagging required

2. IP Addressing
   - VLAN 10: Must use 10.10.10.0/24
   - VLAN 20: Must use 10.10.20.0/24
   - No 172.x.x.x addresses allowed
   - Static IPs must be in respective reserved ranges

3. Network Security
   - Bridge must have ICC enabled for VLAN 20
   - IP masquerade enabled for container network
   - MAC address binding required
   - Port exposure only through Traefik
   - Inter-VLAN routing must follow ACL rules

4. Monitoring
   - Network utilization tracking per VLAN
   - Connection state monitoring
   - Security event logging
   - Performance metrics collection
   - VLAN traffic analysis