[![cloudflared](https://github.com/sholdee/caddy-proxy-cloudflare/workflows/CI/badge.svg)](https://github.com/sholdee/caddy-proxy-cloudflare/actions) [![pull](https://img.shields.io/docker/pulls/sholdee/caddy-proxy-cloudflare)](https://img.shields.io/docker/pulls/sholdee/caddy-proxy-cloudflare) [![pull](https://img.shields.io/docker/image-size/sholdee/caddy-proxy-cloudflare)](https://img.shields.io/docker/image-size/sholdee/caddy-proxy-cloudflare)
[![contributions welcome](https://img.shields.io/badge/contributions-welcome-brightgreen.svg?style=flat)](https://ionut.vip)


# Caddy reverse proxy with cloudflare plugin

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

This docker image is based on work from [@lucaslorentz](https://github.com/lucaslorentz/caddy-docker-proxy) which I included the [Cloudflare DNS-01 module](https://github.com/caddy-dns/cloudflare) and [Cloudflare IP module](https://github.com/WeidiDeng/caddy-cloudflare-ip). It is statically-linked and built with a non-root distroless base image that does not include a shell or other OS utilities.

:notebook_with_decorative_cover: If you need more details about how to use this image I will advise you to go to his GitHub and review the [documentation](https://github.com/lucaslorentz/caddy-docker-proxy).

It is useful if you are planning to use the reverse proxy from :tm: [Caddy](https://caddyserver.com/) together with [Let's Encrypt](https://letsencrypt.org/) and [Cloudflare DNS](https://www.cloudflare.com/dns/) as a challenge. 

The main purpose of creating this image is to have DNS challenge for **wildcard domains**. 

Renovate scans for and submits pull requests for dependency updates as they become avaialable. Whenever the repository is updated, a new image is built and pushed by Github Actions.

:interrobang: Note: you will need **the scoped API token** for this setup. Please analyze this **[link](https://github.com/libdns/cloudflare#authenticating)**.


<!-- GETTING STARTED -->
## Getting Started

:beginner: It will work on any Linux box amd64 or arm64. 

### Prerequisites

[![Made with Docker !](https://img.shields.io/badge/Made%20with-Docker-blue)](https://github.com/sholdee/caddy-proxy-cloudflare/blob/main/Dockerfile)

You will need to have:

* :whale: [Docker](https://docs.docker.com/engine/install/)
* :whale2: [docker-compose](https://docs.docker.com/compose/) 
* Domain name -> you can get from [Name Cheap](https://www.namecheap.com)
* [Cloudflare DNS Zone](https://www.cloudflare.com/en-gb/learning/dns/glossary/dns-zone/)

<!-- USAGE -->
## Usage

### Docker Compose

:warning: You will have to use **labels** in docker-compose deployment. Please review below what it means each [label](https://caddyserver.com/docs/caddyfile/directives/tls). :arrow_down:

You will tell :tm: [Caddy](https://caddyserver.com/) where it has to route traffic in docker network, as :tm: [Caddy](https://caddyserver.com/) is **ingress** on this case. 

:arrow_down: A [docker-compose.yml](https://docs.docker.com/compose/) example with a wildcard domain, external services, trusted proxies, and least-privilege container:

```
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
      - no-new-privileges:true                                     # deny priviledge escalation
    read_only: true                                                # set read-only root filesystem
    networks:
      - caddy
    restart: unless-stopped
    volumes:
      - "/var/run/docker.sock:/var/run/docker.sock:ro"             # need socket to read labels and events
      - "/opt/docker/caddy/data:/data:rw"                          # need for certiticate storage, make sure to chown -R 65532:65532
      - "/opt/docker/caddy/config:/config:rw"                      # Caddyfile.autosave location, make sure to chown -R 65532:65532, can also use tmpfs instead
    ports:
      - "80:80/tcp"
      - "443:443/tcp"
    labels:                                                        # global options
      caddy.email: "email@example.com"                             # need for ACME cert regsitration account
      caddy.acme_dns: "cloudflare TOKEN"                           # replace TOKEN with your Cloudflare API token
      caddy.servers.trusted_proxies: "cloudflare"                  # trust Cloudflare IP proxy headers via caddy-cloudflare-ip module
      caddy.servers.trusted_proxies.interval: "1h"                 # optional Cloudflare IP refresh interval, default is 24h
      caddy.servers.trusted_proxies.timeout: "15s"                 # time to wait for response from Cloudflare, default is no timeout
      caddy.servers.client_ip_headers: "Cf-Connecting-Ip"          # use Cf-Connecting-Ip header as the client IP
      caddy.servers.trusted_proxies_strict:                        # use strict processing of client_ip_headers
      caddy.log.output: "stdout"                                   # set global option to log to stdout
      caddy.log.format: "console"                                  # set global option to use console log format
      caddy_0: "*.domain.com"                                      # example labels for proxying an external service by IP
      caddy_0.log:                                                 # enable logging for *.domain.com block
      caddy_0.1_@service: "host service.domain.com"
      caddy_0.1_handle: "@service"
      caddy_0.1_handle.reverse_proxy: http://10.1.1.10:8080
      caddy_0.1_handle.reverse_proxy.header_up: "X-Forwarded-For {client_ip}" # set X-Forwarded-For header to client_ip
      caddy_1: "*.domain.com"
      caddy_1.1_@example: "host example.domain.com"
      caddy_1.1_handle: "@example"
      caddy_1.1_handle.reverse_proxy: http://10.1.1.20:8000
      caddy_1.1_handle.reverse_proxy.header_up: "X-Forwarded-For {client_ip}"

  whoami:
    container_name: whoami                                         # hostname that will resolve within the Docker network
    image: jwilder/whoami:latest
    user: 65532:65532
    privileged: false
    cap_drop:
      - ALL
    security_opt:
      - no-new-privileges:true
    read_only: true
    tmpfs:
      - /tmp
    networks:
      - caddy
    restart: unless-stopped
    labels:
      caddy: "*.domain.com"
      caddy.1_@whoami: "host whoami.domain.com"
      caddy.1_handle: "@whoami"
      caddy.1_handle.reverse_proxy: "{{upstreams 8000}}"           # set http port that caddy will send traffic
      caddy.1_handle.reverse_proxy.header_up: "X-Forwarded-For {client_ip}"
```
> Please get your scoped API-Token from  **[here](https://github.com/libdns/cloudflare#authenticating)**.

:arrow_up: [Go on TOP](#about-the-project) :point_up:

### Testing

:arrow_down: Your can run the following command to see that is working:
 
```
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

:hearts: On the status column of the docker, you will notice the `healthy` word. This is telling you that docker is running [healtcheck](https://scoutapm.com/blog/how-to-use-docker-healthcheck) itself in order to make sure it is working properly. 

:arrow_down: Please test yourself using the following command:

```
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

<!-- LICENSE -->
## License

:newspaper_roll: Distributed under the MIT license. See [LICENSE](https://raw.githubusercontent.com/homeall/caddy-reverse-proxy-cloudflare/main/LICENSE) for more information.

<!-- CONTACT -->
## Contact

:red_circle: Please free to open a ticket on Github.

<!-- ACKNOWLEDGEMENTS -->
## Acknowledgements

 * :tada: [@lucaslorentz](https://github.com/lucaslorentz/caddy-docker-proxy) :trophy:
 * :tada: :tm: [@Caddy](https://github.com/caddyserver/caddy) :1st_place_medal: and its huge :medal_military: **community** :heavy_exclamation_mark:
 * :tada: [dns.providers.cloudflare](https://github.com/caddy-dns/cloudflare) :medal_sports:

:arrow_up: [Go on TOP](#about-the-project) :point_up:
