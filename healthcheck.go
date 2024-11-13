package main

import (
    "net/http"
    "os"
    "time"
)

func main() {
    client := &http.Client{
        Timeout: 5 * time.Second,
    }

    req, err := http.NewRequest("GET", "http://127.0.0.1:2019/config/", nil)
    if err != nil {
        os.Exit(1)
    }
    req.Host = "127.0.0.1:2019"

    // Perform the request
    resp, err := client.Do(req)
    if err != nil || resp.StatusCode != http.StatusOK {
        os.Exit(1)
    }

    os.Exit(0)
}
