// Validate retained remote MCP URL syntax without reading variables or connecting.
package main

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/netip"
	"net/url"
	"os"
	"strconv"
	"strings"
	"unicode"
)

// templateURL substitutes neutral syntax witnesses, never environment values.
// Literal defaults remain observable and must form a supported endpoint.
func templateURL(raw string) (string, bool) {
	var result strings.Builder
	for {
		start := strings.Index(raw, "${")
		if start < 0 {
			result.WriteString(raw)
			return result.String(), true
		}
		result.WriteString(raw[:start])
		end := strings.IndexByte(raw[start+2:], '}')
		if end < 0 {
			return "", false
		}
		end += start + 2
		name, fallback, hasDefault := strings.Cut(raw[start+2:end], ":-")
		if name == "" {
			return "", false
		}
		for i, c := range name {
			if !(c >= 'a' && c <= 'z' || c >= 'A' && c <= 'Z' || c == '_' || i > 0 && c >= '0' && c <= '9') {
				return "", false
			}
		}
		rest := raw[end+1:]
		if hasDefault {
			if strings.Contains(fallback, "${") {
				return "", false
			}
			result.WriteString(fallback)
		} else if result.Len() == 0 && strings.HasPrefix(rest, "://") {
			result.WriteString("https")
		} else if result.Len() == 0 {
			result.WriteString("https://example.invalid")
		} else if strings.HasSuffix(result.String(), "[") && (strings.HasPrefix(rest, "]") || strings.HasPrefix(rest, "%25")) {
			// A whole bracketed host needs an IPv6 witness, not a hostname.
			result.WriteString("::1")
		} else if strings.HasSuffix(result.String(), "%") {
			// A template can supply both hexadecimal digits of an escape.
			result.WriteString("00")
		} else {
			// A number is valid in hostname, port, userinfo, path and query positions.
			result.WriteString("1")
		}
		raw = rest
	}
}

func isHex(c byte) bool {
	return c >= '0' && c <= '9' || c >= 'a' && c <= 'f' || c >= 'A' && c <= 'F'
}

func validRemoteURL(raw string) bool {
	value, ok := templateURL(raw)
	if !ok || strings.ContainsFunc(value, func(c rune) bool { return unicode.IsSpace(c) || unicode.IsControl(c) }) {
		return false
	}
	// net/url validates path escapes but retains raw query text; inspect all escapes.
	for i := 0; i < len(value); i++ {
		if value[i] == '%' {
			if i+2 >= len(value) || !isHex(value[i+1]) || !isHex(value[i+2]) {
				return false
			}
			i += 2
		}
	}
	parsed, err := url.Parse(value)
	if err != nil || parsed.Hostname() == "" || parsed.Opaque != "" ||
		!strings.EqualFold(parsed.Scheme, "http") && !strings.EqualFold(parsed.Scheme, "https") {
		return false
	}
	if strings.HasPrefix(parsed.Host, "[") {
		address, err := netip.ParseAddr(parsed.Hostname())
		if err != nil || !address.Is6() {
			return false
		}
	} else if strings.Contains(parsed.Hostname(), ":") {
		return false // IPv6 literals require brackets.
	}
	if port := parsed.Port(); port != "" {
		number, err := strconv.ParseUint(port, 10, 16)
		if err != nil || number > 65535 {
			return false
		}
	}
	_, err = http.NewRequest(http.MethodGet, value, nil)
	return err == nil
}

func validateURLs(input io.Reader) error {
	const limit = 8 << 20
	data, err := io.ReadAll(io.LimitReader(input, limit+1))
	if err != nil || len(data) > limit {
		return errors.New("remote MCP URL observation is incomplete or exceeds 8 MiB")
	}
	var entries []json.RawMessage
	if err := json.Unmarshal(data, &entries); err != nil || entries == nil {
		return errors.New("remote MCP URL observation must be one complete array")
	}
	for i, entry := range entries {
		var value string
		if string(entry) == "null" || json.Unmarshal(entry, &value) != nil || !validRemoteURL(value) {
			return fmt.Errorf("malformed remote MCP URL at entry %d", i+1)
		}
	}
	return nil
}

func main() {
	if err := validateURLs(os.Stdin); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}
