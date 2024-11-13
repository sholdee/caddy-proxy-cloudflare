package main

import (
    "net"
    "os"
    "strings"
    "time"
)

func main() {
    // Set up a connection to the Caddy admin API
    conn, err := net.DialTimeout("tcp", "127.0.0.1:2019", 5*time.Second)
    if err != nil {
        os.Exit(1)
    }
    defer conn.Close()

    // Craft a minimal HTTP GET request
    request := "GET /config HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n"
    _, err = conn.Write([]byte(request))
    if err != nil {
        os.Exit(1)
    }

    // Read the response
    buf := make([]byte, 1024)
    n, err := conn.Read(buf)
    if err != nil {
        os.Exit(1)
    }

    // Check if the response contains "200 OK"
    response := string(buf[:n])
    if strings.Contains(response, "200 OK") {
        os.Exit(0)
    }

    os.Exit(1)
}
