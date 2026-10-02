package main

import (
	"go/ast"
	"go/token"
	"strconv"
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
		{"named argv", `package p; type argv []string; var x = argv{"--json", "merged"}`, "--json merged", false},
		{"inferred nested argv", `package p; var x = [][]string{{"--json", "merged"}}`, "", true},
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

func TestMaximalConcatenation(t *testing.T) {
	parts, err := guidance([]byte("package p; const x = " + strings.Repeat(`"a"+`, 127) + `"a"`))
	if err != nil {
		t.Fatal(err)
	}
	if len(parts) != 1 || parts[0] != strings.Repeat("a", 128) {
		t.Fatal("concatenation prefixes were repeatedly retained")
	}
}

func TestDecodedBudget(t *testing.T) {
	parts, err := guidance([]byte("package p; const x = " + strconv.Quote(strings.Repeat("x", (4<<20)+1))))
	if err == nil || parts != nil {
		t.Fatal("oversized decoded output did not return UNKNOWN")
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

func TestKnownArgumentsAreDecodedOnce(t *testing.T) {
	value := strings.Repeat("x", 1200000)
	d := &decoder{}
	d.joinArgs([]ast.Expr{
		&ast.BasicLit{Kind: token.STRING, Value: `"--json"`},
		&ast.BasicLit{Kind: token.STRING, Value: strconv.Quote(value)},
	})
	if d.err != nil || len(d.parts) != 1 || d.parts[0] != "--json "+value {
		t.Fatalf("known argv was redundantly decoded: %v", d.err)
	}
}
