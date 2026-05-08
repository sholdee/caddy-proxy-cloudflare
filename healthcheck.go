package main

import (
	"net/http"
	"os"
	"time"
)

const (
	caddyAdminConfigURL = "http://127.0.0.1:2019/config/"
	healthcheckTimeout  = 4 * time.Second
)

func main() {
	client := &http.Client{Timeout: healthcheckTimeout}
	os.Exit(runHealthcheck(client, caddyAdminConfigURL))
}

func runHealthcheck(client *http.Client, url string) int {
	resp, err := client.Get(url)
	if err != nil {
		return 1
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return 1
	}

	return 0
}
