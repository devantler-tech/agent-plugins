package main

import (
	"strings"
	"testing"
)

func TestGuidance(t *testing.T) {
	tests := []struct {
		name, source, want string
		unknown            bool
	}{
		{"comment", "package p\n// gh pr view --json merged\n", "--json merged", false},
		{"escaped", `package p; const x = "--json mer\u0067ed"`, "--json merged", false},
		{"raw", "package p; const x = `--json merged`", "--json merged", false},
		{"concatenated", `package p; const x = "--json mer" + "ged"`, "--json merged", false},
		{"command", `package p; var x = exec.Command("gh", "pr", "view", "--json", "merged")`, "--json merged", false},
		{"context", `package p; var x = exec.CommandContext(ctx, "gh", "pr", "view", "--json", "merged")`, "--json merged", false},
		{"dot import", `package p; var x = Command("gh", "pr", "view", "--json", "merged")`, "--json merged", false},
		{"argv", `package p; var x = []string{"--json", "merged"}`, "--json merged", false},
		{"dynamic", `package p; var x = []string{"--json", fields}`, "", true},
		{"dynamic command", `package p; var x = exec.Command("gh", "--json", fields)`, "", true},
		{"keyed argv", `package p; var x = []string{0:"--json", 1:"merged"}`, "", true},
		{"malformed", `package p; func broken(`, "", true},
		{"no execution", `package p; func init(){ panic("never execute") }`, "never execute", false},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			parts, err := guidance([]byte(test.source))
			if (err != nil) != test.unknown {
				t.Fatalf("unknown=%v, error=%v", test.unknown, err)
			}
			if !test.unknown && !strings.Contains(strings.Join(parts, "\n%\n"), test.want) {
				t.Fatalf("missing observed text %q in %q", test.want, parts)
			}
			if test.unknown && parts != nil {
				t.Fatal("incomplete parsing returned partial success")
			}
		})
	}
}

func TestSeparateStrings(t *testing.T) {
	parts, err := guidance([]byte(`package p; var notes = []string{"The CLI option --json", "merged is invalid"}`))
	if err != nil {
		t.Fatal(err)
	}
	for _, part := range parts {
		if strings.Contains(part, "--json merged") {
			t.Fatalf("unrelated notes were joined: %q", part)
		}
	}
}
