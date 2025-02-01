# Project Documentation Index

## System Architecture and Relationships

This documentation set provides a comprehensive overview of the project's architecture, component relationships, and maintenance guidelines.

### Core Documentation Files

1. [Codebase Relationships](./codebase-relationships.md)
   - Complete directory structure
   - File dependencies and relationships
   - Configuration inheritance patterns
   - Maintenance workflows
   - Best practices for modifications
   - Network configuration and IP relationships
   - VLAN segmentation and routing rules
   - Security measures and backup procedures

2. [Architecture Diagrams](./architecture-diagram.md)
   - System component diagram
   - Data flow sequences
   - Configuration inheritance visualization
   - Network topology diagram
   - Port mapping visualization
   - Security flow visualization
   - Detailed network flows
     - Media access flow
     - Media management flow
     - Backup flow
   - Failure scenarios
     - Service failover
     - Network recovery
     - VLAN failure recovery

3. [Network Troubleshooting](./network-troubleshooting.md)
   - Quick diagnostic procedures
   - Common issues and solutions
   - Diagnostic commands reference
   - Recovery procedures
   - Monitoring and prevention
   - Preventive maintenance

### Additional Documentation

- [Network Topology](./network-topology.md)
- [VLAN Management](./vlan-management.md)
- [Network Routing Rules](./network-routing-rules.md)

## Quick Reference

### Key Directories
- `/scripts`: Automation and maintenance scripts
- `/monitoring`: System monitoring configurations
- `/traefik`: Reverse proxy and security settings
- `/docs`: System documentation

### Important Files
- `docker-compose.yml`: Service definitions
- `.env`: Environment configuration
- `deploy.ps1`: Deployment automation
- `test-setup.ps1`: Environment testing

### Network Configuration
- **VLAN Structure**
  - VLAN 20: Media Services (10.20.0.0/24)
  - VLAN 30: Management (10.30.0.0/24)
  - VLAN 40: Storage (10.40.0.0/24)

- **Key Network Services**
  - Traefik: Reverse Proxy (VLAN 30)
  - Media Services: Plex, *arr (VLAN 20)
  - Storage Services: NAS, Backups (VLAN 40)

- **Security**
  - OAuth Authentication
  - VLAN Segregation
  - Firewall Rules
  - VPN Access

- **Troubleshooting**
  - Network diagnostics
  - Service recovery
  - VLAN management
  - Performance monitoring

### Common Tasks

1. **System Updates**
   - Review `codebase-relationships.md` for dependency impacts
   - Follow modification best practices
   - Update relevant documentation

2. **Troubleshooting**
   - Consult architecture diagrams for component relationships
   - Follow network troubleshooting guide
   - Check service-specific logs
   - Review monitoring alerts
   - Verify network connectivity between VLANs
   - Check firewall rules and access logs
   - Use diagnostic commands from troubleshooting guide

3. **Configuration Changes**
   - Follow inheritance patterns in documentation
   - Update all affected components
   - Run test suite
   - Verify network security measures
   - Test inter-VLAN communication
   - Validate service health checks

## Documentation Maintenance

This documentation should be kept up to date when:
1. Adding or removing services
2. Modifying system architecture
3. Changing security configurations
4. Updating deployment procedures
5. Modifying network topology
6. Updating VLAN configurations
7. Changing security policies
8. Adding new troubleshooting procedures
9. Updating recovery processes
10. Modifying monitoring rules

## Contributing

When contributing to the documentation:
1. Follow the existing format and structure
2. Update diagrams when architecture changes
3. Keep the index updated
4. Maintain clear relationships between documents
5. Document network changes thoroughly
6. Update security configurations
7. Add new troubleshooting scenarios
8. Document recovery procedures
9. Update monitoring configurations