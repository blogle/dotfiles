package main

import (
	"io"
	"log"
	"net/http"
	"net/http/httputil"
	"net/url"
	"strconv"
	"strings"

	"golang.org/x/text/encoding/charmap"
	"golang.org/x/text/transform"
)

func main() {
	target, _ := url.Parse("http://localhost:8888")
	proxy := httputil.NewSingleHostReverseProxy(target)

	originalDirector := proxy.Director
	proxy.Director = func(req *http.Request) {
		originalDirector(req)
	}

	proxy.ModifyResponse = func(resp *http.Response) error {
		contentType := resp.Header.Get("Content-Type")
		if isPlaylistContentType(contentType) {
			body, err := io.ReadAll(resp.Body)
			if err != nil {
				return err
			}
			resp.Body.Close()

			utf8Body := fixEncoding(body)
			resp.Header.Set("Content-Length", strconv.Itoa(len(utf8Body)))
			resp.Header.Set("Content-Type", "application/x-mpegurl; charset=utf-8")
			resp.Body = io.NopCloser(strings.NewReader(utf8Body))
		}
		return nil
	}

	log.Println("Charset proxy listening on :8889")
	log.Fatal(http.ListenAndServe(":8889", proxy))
}

func isPlaylistContentType(contentType string) bool {
	ct := strings.ToLower(contentType)
	return strings.Contains(ct, "mpegurl") ||
		strings.Contains(ct, "m3u") ||
		strings.Contains(ct, "video/mp2t")
}

func fixEncoding(b []byte) string {
	if isValidUTF8(b) {
		return string(b)
	}
	decoder := charmap.ISO8859_1.NewDecoder()
	reader := transform.NewReader(strings.NewReader(string(b)), decoder)
	result, _ := io.ReadAll(reader)
	return string(result)
}

func isValidUTF8(b []byte) bool {
	for i := 0; i < len(b); {
		r, size := decodeRune(b[i:])
		if r == '\uFFFD' && size == 1 {
			return false
		}
		i += size
	}
	return true
}

func decodeRune(b []byte) (rune, int) {
	if len(b) == 0 {
		return '\uFFFD', 1
	}
	c := b[0]
	if c < 0x80 {
		return rune(c), 1
	}
	if c < 0xC0 {
		return '\uFFFD', 1
	}
	if c < 0xE0 {
		if len(b) < 2 || b[1]&0xC0 != 0x80 {
			return '\uFFFD', 1
		}
		return rune(c&0x1F)<<6 | rune(b[1]&0x3F), 2
	}
	if c < 0xF0 {
		if len(b) < 3 || b[1]&0xC0 != 0x80 || b[2]&0xC0 != 0x80 {
			return '\uFFFD', 1
		}
		return rune(c&0x0F)<<12 | rune(b[1]&0x3F)<<6 | rune(b[2]&0x3F), 3
	}
	if c < 0xF8 {
		if len(b) < 4 || b[1]&0xC0 != 0x80 || b[2]&0xC0 != 0x80 || b[3]&0xC0 != 0x80 {
			return '\uFFFD', 1
		}
		return rune(c&0x07)<<18 | rune(b[1]&0x3F)<<12 | rune(b[2]&0x3F)<<6 | rune(b[3]&0x3F), 4
	}
	return '\uFFFD', 1
}