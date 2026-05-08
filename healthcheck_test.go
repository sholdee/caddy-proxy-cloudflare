package main

import (
	"errors"
	"io"
	"net/http"
	"strings"
	"testing"
)

func TestRunHealthcheckSucceedsOnOK(t *testing.T) {
	var gotMethod string
	var gotPath string
	client := &http.Client{Transport: roundTripFunc(func(r *http.Request) (*http.Response, error) {
		gotMethod = r.Method
		gotPath = r.URL.Path
		return response(http.StatusOK), nil
	})}

	if code := runHealthcheck(client, "http://127.0.0.1:2019/config/"); code != 0 {
		t.Fatalf("runHealthcheck() = %d, want 0", code)
	}

	if gotMethod != http.MethodGet {
		t.Fatalf("request method = %q, want %q", gotMethod, http.MethodGet)
	}
	if gotPath != "/config/" {
		t.Fatalf("request path = %q, want /config/", gotPath)
	}
}

func TestRunHealthcheckFailsOnNonOKStatus(t *testing.T) {
	client := &http.Client{Transport: roundTripFunc(func(r *http.Request) (*http.Response, error) {
		return response(http.StatusServiceUnavailable), nil
	})}

	if code := runHealthcheck(client, "http://127.0.0.1:2019/config/"); code != 1 {
		t.Fatalf("runHealthcheck() = %d, want 1", code)
	}
}

func TestRunHealthcheckClosesResponseBody(t *testing.T) {
	body := &closeRecorder{}
	client := &http.Client{Transport: roundTripFunc(func(r *http.Request) (*http.Response, error) {
		return responseWithBody(http.StatusServiceUnavailable, body), nil
	})}

	if code := runHealthcheck(client, "http://127.0.0.1:2019/config/"); code != 1 {
		t.Fatalf("runHealthcheck() = %d, want 1", code)
	}
	if !body.closed {
		t.Fatal("response body was not closed")
	}
}

func TestRunHealthcheckFailsOnRequestError(t *testing.T) {
	client := &http.Client{Transport: roundTripFunc(func(r *http.Request) (*http.Response, error) {
		return nil, errors.New("request failed")
	})}

	if code := runHealthcheck(client, "http://127.0.0.1:2019/config/"); code != 1 {
		t.Fatalf("runHealthcheck() = %d, want 1", code)
	}
}

type roundTripFunc func(*http.Request) (*http.Response, error)

func (f roundTripFunc) RoundTrip(r *http.Request) (*http.Response, error) {
	return f(r)
}

func response(statusCode int) *http.Response {
	return responseWithBody(statusCode, io.NopCloser(strings.NewReader("")))
}

func responseWithBody(statusCode int, body io.ReadCloser) *http.Response {
	return &http.Response{
		StatusCode: statusCode,
		Body:       body,
		Header:     make(http.Header),
	}
}

type closeRecorder struct {
	closed bool
}

func (b *closeRecorder) Read([]byte) (int, error) {
	return 0, io.EOF
}

func (b *closeRecorder) Close() error {
	b.closed = true
	return nil
}
