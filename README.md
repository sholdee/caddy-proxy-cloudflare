[![cloudflared](https://github.com/sholdee/caddy-proxy-cloudflare/workflows/CI/badge.svg)](https://github.com/sholdee/caddy-proxy-cloudflare/actions) [![pull](https://img.shields.io/docker/pulls/sholdee/caddy-proxy-cloudflare)](https://img.shields.io/docker/pulls/sholdee/caddy-proxy-cloudflare) [![pull](https://img.shields.io/docker/image-size/sholdee/caddy-proxy-cloudflare)](https://img.shields.io/docker/image-size/sholdee/caddy-proxy-cloudflare)
[![contributions welcome](https://img.shields.io/badge/contributions-welcome-brightgreen.svg?style=flat)](https://ionut.vip)


# Caddy with Docker proxy, Cloudflare, and Crowdsec bouncer modules

<!-- TABLE OF CONTENTS -->
<details open="open">
  <summary>Table of Contents</summary>
  <ol>
    <li>
      <a href="#about-the-project">About The Project</a>
    </li>
    <li>
      <a href="#getting-started">Getting Started</a>
      <ul>
        <li><a href="#prerequisites">Prerequisites</a></li>
      </ul>
    </li>
    <li>
      <a href="#usage">Usage</a>
      <ul>
        <li><a href="#docker-compose">Docker-compose</a></li>
      </ul>
        <ul>
        <li><a href="#testing">Testing</a></li>
      </ul>
    </li>
    <li><a href="#license">License</a></li>
    <li><a href="#contact">Contact</a></li>
    <li><a href="#acknowledgements">Acknowledgements</a></li>
  </ol>
</details>

<!-- ABOUT THE PROJECT -->
## About The Project

This image is designed to be used with Docker Compose and includes the following modules:

* [Docker proxy module](https://github.com/lucaslorentz/caddy-docker-proxy) for Caddy configuration via Docker labels
* [Cloudflare DNS-01 module](https://github.com/caddy-dns/cloudflare) for DNS-01 domain control validation and wildcard certs
* [Cloudflare IP module](https://github.com/WeidiDeng/caddy-cloudflare-ip) for trusting proxy headers from Cloudflare CDN
* [Crowdsec bouncer module](https://github.com/hslatman/caddy-crowdsec-bouncer) for layer 7 enforcement of Crowdsec decisions

It is statically-linked and built with a non-root distroless base image that does not include a shell or other OS utilities.

:notebook_with_decorative_cover: If you need more details about how to configure Caddy via the Docker proxy module please refer to the [documentation](https://github.com/lucaslorentz/caddy-docker-proxy).

The main purpose of creating this image is to have DNS challenge for **wildcard domains** on Cloudflare and optional Crowdsec integration. With the Cloudflare IP module, we can dynamically trust their CDN IP addresses for Cloudflare-proxied domains, enabling Caddy to resolve the real client IP addresses for inbound connections. Crowdsec will then use this for layer 7 enforcement of decisions.

Renovate scans for and submits pull requests for dependency updates as they become available. Whenever the repository is updated, a new image is built and pushed by Github Actions.

:interrobang: Note: you will need a **scoped API token** for this setup. Please refer to this **[link](https://github.com/libdns/cloudflare#authenticating)**.

<!-- GETTING STARTED -->
## Getting Started

:beginner: It will work on any Linux box amd64 or arm64. 

### Prerequisites

[![Made with Docker !](https://img.shields.io/badge/Made%20with-Docker-blue)](https://github.com/sholdee/caddy-proxy-cloudflare/blob/main/Dockerfile)

You will need to have:

* :whale: [Docker](https://docs.docker.com/engine/install/)
* :whale2: [docker-compose](https://docs.docker.com/compose/) 
* [Domain name](https://www.cloudflare.com/products/registrar/)
* [Cloudflare DNS Zone](https://www.cloudflare.com/en-gb/learning/dns/glossary/dns-zone/)

<!-- USAGE -->
## Usage

### Docker Compose

:warning: You will have to use **labels** in the docker-compose deployment. Please review the example below. :arrow_down:

:arrow_down: A [docker-compose.yml](https://docs.docker.com/compose/) example with a wildcard domain, external services, trusted proxies, Crowdsec integration, and least-privilege containers:

```yaml
services:

  caddy:
    container_name: caddy
    image: sholdee/caddy-proxy-cloudflare:latest
    user: 65532:65532                                              # use non-root user
    group_add:                                                     # add docker group ID from /etc/group for docker socket access
      - 123
    privileged: false
    cap_drop:
      - ALL                                                        # drop all capabilities
    cap_add:
      - NET_BIND_SERVICE                                           # add NET_BIND_SERVICE to bind ports <=1024
    security_opt:
      - no-new-privileges:true                                     # deny privilege escalation
    read_only: true                                                # set read-only root filesystem
    tmpfs:                                                         # autosaved config does not need to be persisted
      - /config
    networks:
      - caddy
    dns:                                                           # set container DNS to Cloudflare
      - 1.1.1.1
      - 1.0.0.1
    restart: unless-stopped
    volumes:
      - "/var/run/docker.sock:/var/run/docker.sock:ro"             # need socket to read labels and events
      - "/opt/docker/caddy/data:/data:rw"                          # need for certiticate storage, make sure to chown -R 65532:65532
    ports:
      - "80:80/tcp"
      - "443:443/tcp"
    labels:                                                        # global options
      caddy.email: "email@example.com"                             # need for ACME cert regsitration account
      caddy.acme_dns: "cloudflare ${CF_TOKEN}"                     # replace ${CF_TOKEN} with your Cloudflare API token
      caddy.servers.trusted_proxies: "cloudflare"                  # trust Cloudflare IP proxy headers via caddy-cloudflare-ip module
      caddy.servers.trusted_proxies.interval: "1h"                 # optional Cloudflare IP refresh interval, default is 24h
      caddy.servers.trusted_proxies.timeout: "15s"                 # time to wait for response from Cloudflare, default is no timeout
      caddy.servers.client_ip_headers: "Cf-Connecting-Ip"          # use Cf-Connecting-Ip header as the client IP
      caddy.servers.trusted_proxies_strict:                        # use strict processing of client_ip_headers
      caddy.log.output: "stdout"                                   # set global option to log to stdout
      caddy.persist_config: "off"                                  # persist_config not needed with docker proxy module configuration
      caddy.crowdsec.api_url: "http://crowdsec:8080"               # api url for crowdsec container
      caddy.crowdsec.api_key: "${CROWDSEC_API_KEY}"                # crowdsec api key that is set for caddy
      caddy.crowdsec.ticker_interval: "3s"                         # crowdsec local api poll interval for stream bouncer
      caddy_0: "*.domain.com"                                      # example labels for proxying an external service by IP
      caddy_0.log:                                                 # enable logging for *.domain.com block
      caddy_0.1_@service: "host service.domain.com"
      caddy_0.1_handle: "@service"
      caddy_0.1_handle.route.crowdsec:                             # add crowdsec to this upstream via route block
      caddy_0.1_handle.route.reverse_proxy: http://10.1.1.10:8080
      caddy_0.1_handle.route.reverse_proxy.header_up: "X-Forwarded-For {client_ip}" # set X-Forwarded-For header to client_ip
      caddy_1: "*.domain.com"
      caddy_1.1_@example: "host example.domain.com"
      caddy_1.1_handle: "@example"
      caddy_1.1_handle.route.crowdsec:
      caddy_1.1_handle.route.reverse_proxy: http://10.1.1.20:8000
      caddy_1.1_handle.route.reverse_proxy.header_up: "X-Forwarded-For {client_ip}"

  crowdsec:
    container_name: crowdsec
    image: crowdsecurity/crowdsec:latest
    user: 65532:65532
    group_add:
      - 123
    privileged: false
    cap_drop:
      - ALL
    security_opt:
      - no-new-privileges:true
    networks:
      - caddy
    environment:
      - TZ=America/Chicago
      - GID=65532
      - USE_WAL=true
      - COLLECTIONS=crowdsecurity/linux crowdsecurity/caddy crowdsecurity/whitelist-good-actors # base collections for caddy
      - PARSERS=crowdsecurity/whitelists                          # whitelist internal ip addresses
      - BOUNCER_KEY_CADDY=${CROWDSEC_API_KEY}                     # the api key that will be set for caddy
      - ENROLL_KEY=${ENROLL_KEY}                                  # optional enrollment key for crowdsec hub
    volumes:
      - /opt/docker/crowdsec/data:/var/lib/crowdsec/data:rw       # crowdsec data dir
      - /opt/docker/crowdsec/config:/etc/crowdsec:rw              # crowdsec config dir
      - /opt/docker/crowdsec/acquis.yaml:/etc/crowdsec/acquis.yaml:ro # our log sources config
      - /var/run/docker.sock:/var/run/docker.sock:ro              # need to mount docker socket to read stdout logs
    restart: unless-stopped

  whoami:
    container_name: whoami
    image: jwilder/whoami:latest
    hostname: TheDocker                                           # Expected result using curl
    user: 65532:65532
    privileged: false
    cap_drop:
      - ALL
    security_opt:
      - no-new-privileges:true
    read_only: true
    networks:
      - caddy
    restart: unless-stopped
    labels:
      caddy: "*.domain.com"
      caddy.1_@whoami: "host whoami.domain.com"
      caddy.1_handle: "@whoami"
      caddy.1_handle.route.crowdsec:
      caddy.1_handle.route.reverse_proxy: "{{upstreams 8000}}"    # set http port that caddy will send traffic
      caddy.1_handle.route.reverse_proxy.header_up: "X-Forwarded-For {client_ip}"

```

If using Crowdsec, you will also need to create and mount acquis.yaml to the container for your log source(s):

```yaml
source: docker
container_name:
 - caddy
labels:
  type: caddy

```

> Please get your scoped Cloudflare API token from  **[here](https://github.com/libdns/cloudflare#authenticating)**.

:arrow_up: [Go on TOP](#about-the-project) :point_up:

### Testing

:arrow_down: Your can run the following command to see that is working:
 
```bash
$  curl --insecure -vvI https://test.ionut.vip 2>&1 | awk 'BEGIN { cert=0 } /^\* Server certificate:/ { cert=1 } /^\*/ { if (cert) print }'
* Server certificate:
*  subject: CN=test.ionut.vip ################################ CA from Let's Enctrypt Staging 
*  start date: Jan  5 15:15:00 2021 GMT
*  expire date: Apr  5 15:15:00 2021 GMT
*  issuer: CN=Fake LE Intermediate X1 ######################## This is telling you that acme is working as expected!
*  SSL certificate verify result: unable to get local issuer certificate (20), continuing anyway.
* Using HTTP2, server supports multi-use
* Connection state changed (HTTP/2 confirmed)
* Copying HTTP/2 data in stream buffer to connection buffer after upgrade: len=0
* Using Stream ID: 1 (easy handle 0x7fc02180ec00)
* TLSv1.3 (IN), TLS handshake, Newsession Ticket (4):
* Connection state changed (MAX_CONCURRENT_STREAMS == 250)!
$  curl -k https://test.ionut.vip
I'm TheDocker################################### Expected result from hostname above
```
![](./assets/caddy-reverse-proxy.gif)

:hearts: On the status column of the docker, you will notice the `healthy` word. This is telling you that docker is running [healthcheck](https://scoutapm.com/blog/how-to-use-docker-healthcheck) itself in order to make sure it is working properly. 

:arrow_down: Please test yourself using the following command:

```bash
❯ docker inspect --format "{{json .State.Health }}" caddy | jq
{
  "Status": "healthy",
  "FailingStreak": 0,
  "Log": [
    {
      "Start": "2021-01-04T11:10:49.2975799Z",
      "End": "2021-01-04T11:10:49.3836437Z",
      "ExitCode": 0,
      "Output": ""
    }
  ]
}
```

To verify that Crowdsec is parsing logs, check the metrics:

```bash
❯ sudo docker exec crowdsec cscli metrics
Acquisition Metrics:
+-----------------------------------------+------------+--------------+----------------+------------------------+-------------------+
| Source                                  | Lines read | Lines parsed | Lines unparsed | Lines poured to bucket | Lines whitelisted |
+-----------------------------------------+------------+--------------+----------------+------------------------+-------------------+
| docker:caddy                            | 14.90k     | 14.90k       | -              | 1.11k                  | 3.11k             |
+-----------------------------------------+------------+--------------+----------------+------------------------+-------------------+
```

<!-- LICENSE -->
## License

:newspaper_roll: Distributed under the Eclipse Public License 2.0. See [LICENSE](https://raw.githubusercontent.com/homeall/caddy-reverse-proxy-cloudflare/main/LICENSE) for more information.

<!-- CONTACT -->
## Contact

:red_circle: Please free to open a ticket on Github.

<!-- ACKNOWLEDGEMENTS -->
## Acknowledgements

 * :tada: [@lucaslorentz](https://github.com/lucaslorentz/caddy-docker-proxy) :trophy:
 * :tada: :tm: [@Caddy](https://github.com/caddyserver/caddy) :1st_place_medal: and its huge :medal_military: **community** :heavy_exclamation_mark:
 * :tada: [dns.providers.cloudflare](https://github.com/caddy-dns/cloudflare) :medal_sports:
 * :tada: [http.ip_sources.cloudflare](https://github.com/WeidiDeng/caddy-cloudflare-ip) :boom:
 * :tada: [crowdsec](https://github.com/hslatman/caddy-crowdsec-bouncer) :star2:

:arrow_up: [Go on TOP](#about-the-project) :point_up:
