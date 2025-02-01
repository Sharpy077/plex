# System Architecture Diagram

## Core System Components and Relationships

```mermaid
graph TB
    subgraph External["External Access"]
        Internet["Internet"]
        RemoteUsers["Remote Users"]
    end

    subgraph ReverseProxy["Reverse Proxy Layer"]
        Traefik["Traefik"]
        SSL["SSL/TLS"]
        OAuth["OAuth"]
    end

    subgraph Security["Security Layer"]
        Headers["Security Headers"]
        Middleware["Middleware Chain"]
        VLAN["VLAN Management"]
    end

    subgraph Services["Core Services"]
        Plex["Plex Media Server"]
        subgraph MediaManagement["Media Management"]
            Radarr["Radarr"]
            Sonarr["Sonarr"]
            Lidarr["Lidarr"]
            Readarr["Readarr"]
        end
    end

    subgraph Storage["Storage Layer"]
        Media["Media Storage"]
        Downloads["Downloads"]
        Backups["Backups"]
        Configs["Configurations"]
    end

    subgraph Monitoring["Monitoring Stack"]
        Prometheus["Prometheus"]
        Alertmanager["Alertmanager"]
        Dashboards["Dashboards"]
    end

    subgraph Automation["Automation"]
        Scripts["Scripts"]
        Tests["Tests"]
        Deployment["Deployment"]
    end

    %% External connections
    Internet --> Traefik
    RemoteUsers --> Traefik

    %% Reverse proxy connections
    Traefik --> SSL
    Traefik --> OAuth
    SSL --> Headers
    OAuth --> Headers

    %% Security layer connections
    Headers --> Middleware
    Middleware --> VLAN
    VLAN --> Services

    %% Service connections
    MediaManagement --> Plex
    Radarr --> Media
    Sonarr --> Media
    Lidarr --> Media
    Readarr --> Media
    Downloads --> MediaManagement

    %% Monitoring connections
    Services --> Prometheus
    Prometheus --> Alertmanager
    Prometheus --> Dashboards

    %% Automation connections
    Scripts --> Services
    Scripts --> Monitoring
    Tests --> Services
    Deployment --> Services

    %% Storage connections
    Configs --> Services
    Backups --> Services
    Media --> Plex

    classDef external fill:#f9f,stroke:#333,stroke-width:2px
    classDef security fill:#ff9,stroke:#333,stroke-width:2px
    classDef service fill:#9f9,stroke:#333,stroke-width:2px
    classDef storage fill:#99f,stroke:#333,stroke-width:2px
    classDef monitoring fill:#f99,stroke:#333,stroke-width:2px

    class Internet,RemoteUsers external
    class Headers,Middleware,VLAN security
    class Plex,Radarr,Sonarr,Lidarr,Readarr service
    class Media,Downloads,Backups,Configs storage
    class Prometheus,Alertmanager,Dashboards monitoring
```

## Data Flow Diagram

```mermaid
sequenceDiagram
    participant User
    participant Traefik
    participant Auth
    participant Services
    participant Storage
    participant Monitoring

    User->>Traefik: Request Access
    Traefik->>Auth: Validate Request
    Auth-->>Traefik: Authentication Result

    alt is authenticated
        Traefik->>Services: Forward Request
        Services->>Storage: Read/Write Data
        Services-->>User: Response
        Services->>Monitoring: Log Activity
        Monitoring->>Alertmanager: Check Thresholds

        opt Alert Condition Met
            Alertmanager->>Admin: Send Alert
        end
    else is not authenticated
        Traefik-->>User: Access Denied
    end
```

## Configuration Inheritance Diagram

```mermaid
graph TD
    ENV[".env"] --> DC["docker-compose.yml"]
    ENV --> Scripts["scripts/*.ps1"]

    DC --> Services["Service Containers"]
    Scripts --> Monitoring["Monitoring"]

    Services --> Traefik["Traefik Config"]
    Traefik --> Headers["Security Headers"]
    Traefik --> Middle["Middlewares"]

    Services --> Prometheus["Prometheus"]
    Prometheus --> Rules["Alert Rules"]
    Rules --> Alertmanager["Alertmanager"]

    classDef config fill:#f9f,stroke:#333,stroke-width:2px
    classDef service fill:#9f9,stroke:#333,stroke-width:2px
    classDef monitoring fill:#f99,stroke:#333,stroke-width:2px

    class ENV,DC config
    class Services,Traefik service
    class Prometheus,Alertmanager,Rules monitoring
```

## Network Topology Diagram

```mermaid
graph TB
    subgraph Internet["Internet Zone"]
        Web["Web Traffic"]
        VPN["VPN Access"]
    end

    subgraph DMZ["DMZ (VLAN 30)"]
        Traefik
        subgraph Security["Security Services"]
            OAuth["OAuth"]
            WAF["Web Application Firewall"]
        end
    end

    subgraph MediaNet["Media Network (VLAN 20)"]
        subgraph MediaServices["Media Services"]
            Plex
            Radarr
            Sonarr
            Lidarr
        end
    end

    subgraph StorageNet["Storage Network (VLAN 40)"]
        NAS["Network Storage"]
        Backup["Backup Storage"]
        Config["Config Storage"]
    end

    subgraph ManagementNet["Management Network (VLAN 30)"]
        Prometheus
        Alertmanager
        Dashboard["Grafana"]
    end

    %% External Access
    Web --> Traefik
    VPN --> Traefik

    %% DMZ Connections
    Traefik --> OAuth
    OAuth --> WAF
    WAF --> MediaServices
    WAF --> ManagementNet

    %% Internal Network Connections
    MediaServices <--> NAS
    MediaServices <--> Config
    ManagementNet --> MediaServices
    ManagementNet --> StorageNet

    %% Backup Flows
    MediaServices --> Backup
    Config --> Backup

    classDef external fill:#f96,stroke:#333
    classDef dmz fill:#f9f,stroke:#333
    classDef media fill:#9f9,stroke:#333
    classDef storage fill:#99f,stroke:#333
    classDef mgmt fill:#ff9,stroke:#333

    class Web,VPN external
    class Traefik,OAuth,WAF dmz
    class Plex,Radarr,Sonarr,Lidarr media
    class NAS,Backup,Config storage
    class Prometheus,Alertmanager,Dashboard mgmt
```

## Network Port Mapping

```mermaid
graph LR
    subgraph External["External Ports"]
        HTTP["80/TCP"]
        HTTPS["443/TCP"]
        VPN["51820/UDP"]
    end

    subgraph Internal["Internal Ports"]
        subgraph Media["Media Services"]
            Plex["32400/TCP"]
            Arr["7878/TCP<br>8989/TCP<br>8686/TCP"]
        end

        subgraph Monitoring["Monitoring"]
            Prometheus["9090/TCP"]
            NodeExp["9100/TCP"]
        end

        subgraph Storage["Storage"]
            NFS["2049/TCP"]
            SMB["445/TCP"]
        end
    end

    HTTP --> Traefik
    HTTPS --> Traefik
    VPN --> WG["WireGuard"]

    Traefik --> Media
    Traefik --> Monitoring
    WG --> Internal

    classDef external fill:#f96,stroke:#333
    classDef internal fill:#9f9,stroke:#333
    class HTTP,HTTPS,VPN external
    class Plex,Arr,Prometheus,NodeExp,NFS,SMB internal
```

## Detailed Network Flows

### Media Access Flow

```mermaid
sequenceDiagram
    participant User
    participant Traefik
    participant Auth
    participant Plex
    participant Storage
    participant Monitoring

    User->>Traefik: Request Media Access
    Traefik->>Auth: Validate Token

    alt Valid Token
        Auth-->>Traefik: Token Valid
        Traefik->>Plex: Forward Request

        par Media Stream
            Plex->>Storage: Fetch Media
            Storage-->>Plex: Media Data
            Plex-->>User: Stream Media
        and Metrics Collection
            Plex->>Monitoring: Stream Stats
            Monitoring->>Alertmanager: Check Thresholds
        end

    else Invalid Token
        Auth-->>Traefik: Token Invalid
        Traefik-->>User: 401 Unauthorized
        Traefik->>Monitoring: Log Failed Access
    end
```

### Media Management Flow

```mermaid
sequenceDiagram
    participant Radarr
    participant Download
    participant Storage
    participant Plex
    participant Monitor

    Radarr->>Download: Request Media
    activate Download
    Download-->>Radarr: Download Started

    par Download Progress
        Download->>Monitor: Progress Updates
        Monitor->>Alertmanager: Status Check
    end

    Download->>Storage: Save Media
    deactivate Download
    Storage-->>Radarr: Media Ready

    Radarr->>Storage: Process Media
    Storage-->>Radarr: Processing Complete

    Radarr->>Plex: Update Library
    Plex->>Storage: Scan New Media
    Storage-->>Plex: Media Info
    Plex-->>Radarr: Library Updated
```

### Backup Flow

```mermaid
sequenceDiagram
    participant Scheduler
    participant BackupScript
    participant Services
    participant Storage
    participant Monitor

    Scheduler->>BackupScript: Trigger Backup

    par Service Backups
        BackupScript->>Services: Stop Services
        Services-->>BackupScript: Services Stopped
        BackupScript->>Storage: Backup Configs
        Storage-->>BackupScript: Configs Saved
        BackupScript->>Services: Start Services
        Services-->>BackupScript: Services Running
    and Media Backups
        BackupScript->>Storage: Backup Media
        Storage-->>BackupScript: Media Backed Up
    end

    BackupScript->>Monitor: Log Backup Status
    Monitor->>Alertmanager: Check Success
```

## Network Failure Scenarios

### Service Failover

```mermaid
stateDiagram-v2
    [*] --> Primary
    Primary --> Degraded: Service Failure
    Degraded --> Failover: Auto-Switch
    Failover --> Recovery: Auto-Heal
    Recovery --> Primary: Restore

    Primary --> Maintenance: Planned
    Maintenance --> Primary: Complete

    Degraded --> Failed: Cascade
    Failed --> Recovery: Manual

    state Primary {
        [*] --> Active
        Active --> Monitoring
        Monitoring --> Active
    }

    state Failover {
        [*] --> Backup
        Backup --> Verify
        Verify --> Backup
    }
```

### Network Recovery Flow

```mermaid
graph TD
    Start[Failure Detected] --> Monitor[Monitoring Alert]
    Monitor --> Auto[Automatic Recovery]

    Auto --> Check{Check Status}
    Check -->|Success| Normal[Normal Operation]
    Check -->|Failure| Manual[Manual Intervention]

    Manual --> Diagnose[Diagnostic Steps]
    Diagnose --> Network[Network Tests]
    Diagnose --> Services[Service Tests]
    Diagnose --> Storage[Storage Tests]

    Network --> Action[Recovery Action]
    Services --> Action
    Storage --> Action

    Action --> Verify[Verify Recovery]
    Verify --> Check

    Normal --> Log[Log Resolution]
    Log --> Update[Update Documentation]

    classDef alert fill:#f96,stroke:#333
    classDef normal fill:#9f9,stroke:#333
    classDef process fill:#99f,stroke:#333

    class Monitor,Manual alert
    class Normal,Update normal
    class Action,Verify process
```

### VLAN Failure Recovery

```mermaid
sequenceDiagram
    participant Monitor
    participant Network
    participant Services
    participant Backup
    participant Admin

    Monitor->>Network: Detect VLAN Issue
    Network-->>Monitor: Connectivity Lost

    par Alert
        Monitor->>Admin: Send Alert
    and Auto-Recovery
        Monitor->>Network: Try Recovery
    end

    alt Auto-Recovery Success
        Network-->>Monitor: VLAN Restored
        Monitor->>Services: Resume Operations
        Services-->>Monitor: Services Online
    else Auto-Recovery Failed
        Network-->>Monitor: Recovery Failed
        Monitor->>Admin: Escalate Alert
        Admin->>Network: Manual Recovery
        Network-->>Admin: Recovery Status
    end

    opt Backup Required
        Admin->>Backup: Switch to Backup VLAN
        Backup-->>Services: Redirect Traffic
        Services-->>Monitor: Confirm Status
    end
```